import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/files/application/file_explorer_contract.dart';
import 'package:landa/features/files/application/files_feature_state_owner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'landa_files_feature_owner_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'owner controls local explorer navigation, filter, and sort without page-local truth',
    () async {
      final rootDirectory = Directory(p.join(tempDirectory.path, 'incoming'));
      final docsDirectory = Directory(p.join(rootDirectory.path, 'docs'));
      await docsDirectory.create(recursive: true);

      await File(
        p.join(rootDirectory.path, 'zeta.txt'),
      ).writeAsString('zeta', flush: true);
      await File(
        p.join(rootDirectory.path, 'alpha.txt'),
      ).writeAsString('alpha', flush: true);
      await File(
        p.join(docsDirectory.path, 'guide.txt'),
      ).writeAsString('guide', flush: true);

      final owner = FilesFeatureStateOwner(
        roots: <FileExplorerRoot>[
          FileExplorerRoot(label: 'Incoming', path: rootDirectory.path),
        ],
      );

      await owner.initialize();

      expect(owner.state.selectedRoot?.label, 'Incoming');
      expect(owner.state.entries.any((entry) => entry.name == 'docs'), isTrue);

      owner.setSortOption(FilesFeatureSortOption.nameDesc);
      expect(
        owner.state.entries
            .where((entry) => !entry.isDirectory)
            .map((entry) => entry.name)
            .toList(),
        <String>['zeta.txt', 'alpha.txt'],
      );

      owner.setSearchQuery('alpha');
      expect(owner.visibleEntries.map((entry) => entry.name).toList(), <String>[
        'alpha.txt',
      ]);

      owner.setSearchQuery('');
      final docsEntry = owner.state.entries.firstWhere(
        (entry) => entry.isDirectory && entry.name == 'docs',
      );
      await owner.openDirectory(docsEntry);

      expect(owner.relativePathLabel(), 'docs');
      expect(owner.canGoUp, isTrue);
      expect(owner.state.entries.map((entry) => entry.name).toList(), <String>[
        'guide.txt',
      ]);

      await owner.goUp();

      expect(owner.relativePathLabel(), isEmpty);
      expect(
        owner.state.entries.any((entry) => entry.name == 'alpha.txt'),
        isTrue,
      );
    },
  );

  test(
    'owner controls virtual explorer navigation through explicit owner state',
    () async {
      final previewFile = File(p.join(tempDirectory.path, 'photo.jpg'));
      await previewFile.writeAsString('photo', flush: true);

      final owner = FilesFeatureStateOwner(
        roots: <FileExplorerRoot>[
          FileExplorerRoot(
            label: 'My files',
            path: 'virtual://my-files',
            isSharedFolder: true,
            virtualDirectoryLoader: (folderPath) async {
              if (folderPath.isEmpty) {
                return const FileExplorerVirtualDirectory(
                  folders: <FileExplorerVirtualFolder>[
                    FileExplorerVirtualFolder(
                      name: 'Album',
                      folderPath: 'Album',
                    ),
                  ],
                );
              }
              return FileExplorerVirtualDirectory(
                files: <FileExplorerVirtualFile>[
                  FileExplorerVirtualFile(
                    path: previewFile.path,
                    virtualPath: 'Album/photo.jpg',
                    subtitle: 'Album/photo.jpg',
                    sizeBytes: 5,
                    modifiedAt: DateTime.fromMillisecondsSinceEpoch(1000),
                    changedAt: DateTime.fromMillisecondsSinceEpoch(1000),
                  ),
                ],
              );
            },
          ),
        ],
      );

      await owner.initialize();

      expect(owner.state.entries.map((entry) => entry.name).toList(), <String>[
        'Album',
      ]);

      final albumEntry = owner.state.entries.single;
      await owner.openDirectory(albumEntry);

      expect(owner.relativePathLabel(), 'Album');
      expect(owner.state.entries.map((entry) => entry.name).toList(), <String>[
        'photo.jpg',
      ]);

      await owner.goUp();

      expect(owner.relativePathLabel(), isEmpty);
      expect(owner.state.entries.single.name, 'Album');
    },
  );
}

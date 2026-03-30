import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/files/application/preview_cache_owner.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';

import 'test_support/test_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestAppDatabaseHarness harness;
  late SharedFolderCacheRepository sharedFolderCacheRepository;
  late ThumbnailCacheService thumbnailCacheService;
  late SharedCacheIndexStore sharedCacheIndexStore;
  late SharedCacheCatalog sharedCacheCatalog;
  late PreviewCacheOwner previewCacheOwner;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_preview_cache_owner_',
    );
    thumbnailCacheService = ThumbnailCacheService(database: harness.database);
    sharedFolderCacheRepository = SharedFolderCacheRepository(
      database: harness.database,
      thumbnailCacheService: thumbnailCacheService,
    );
    sharedCacheIndexStore = SharedCacheIndexStore(
      database: harness.database,
      thumbnailCacheService: thumbnailCacheService,
    );
    sharedCacheCatalog = SharedCacheCatalog(
      sharedFolderCacheRepository: sharedFolderCacheRepository,
      sharedCacheIndexStore: sharedCacheIndexStore,
    );
    previewCacheOwner = PreviewCacheOwner(
      sharedCacheThumbnailStore: thumbnailCacheService,
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: FileHashService(),
    );
  });

  tearDown(() async {
    previewCacheOwner.dispose();
    sharedCacheCatalog.dispose();
    await harness.dispose();
  });

  test(
    'builds preview transfer artifacts from shared cache truth and cleans up expired preview files',
    () async {
      final sharedRoot = Directory(
        '${harness.rootDirectory.path}${Platform.pathSeparator}shared_docs',
      );
      await sharedRoot.create(recursive: true);
      await File(
        '${sharedRoot.path}${Platform.pathSeparator}readme.txt',
      ).writeAsString('Hello from Landa preview cache owner.', flush: true);

      final upsertResult = await sharedCacheCatalog.upsertOwnerFolderCache(
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        folderPath: sharedRoot.path,
      );
      final previews = await previewCacheOwner
          .buildCompressedPreviewFilesForCache(
            upsertResult.record,
            relativePathFilter: <String>{'readme.txt'},
          );

      expect(previews, hasLength(1));
      expect(previews.single.fileName, 'readme.text-preview.txt');

      final artifactFile = File(previews.single.sourcePath);
      expect(await artifactFile.exists(), isTrue);

      await artifactFile.setLastModified(
        DateTime.now().subtract(const Duration(days: 10)),
      );

      final cleanup = await previewCacheOwner.cleanupPreviewArtifacts(
        maxSizeGb: 1,
        maxAgeDays: 1,
      );

      expect(cleanup.filesDeleted, 1);
      expect(await artifactFile.exists(), isFalse);
    },
  );

  test(
    'loads and reuses audio covers through owner-managed preview cache',
    () async {
      final audioFile = File(
        '${harness.rootDirectory.path}${Platform.pathSeparator}song.mp3',
      );
      await audioFile.writeAsBytes(_buildMp3WithArtwork(_tinyPngBytes()));

      final first = await previewCacheOwner.loadAudioCover(
        filePath: audioFile.path,
        maxExtent: 120,
        quality: 80,
      );

      expect(first, isNotNull);
      expect(first, isNotEmpty);

      final mediaPreviewDirectory = await previewCacheOwner
          .resolveMediaPreviewDirectory();
      expect(await _countFiles(mediaPreviewDirectory), 1);

      previewCacheOwner.clearInMemoryPreviewCache();

      final second = await previewCacheOwner.loadAudioCover(
        filePath: audioFile.path,
        maxExtent: 120,
        quality: 80,
      );

      expect(second, isNotNull);
      expect(second, orderedEquals(first!));
      expect(await _countFiles(mediaPreviewDirectory), 1);
    },
  );
}

Future<int> _countFiles(Directory directory) async {
  var count = 0;
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File) {
      count += 1;
    }
  }
  return count;
}

Uint8List _tinyPngBytes() {
  return Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X3xkAAAAASUVORK5CYII=',
    ),
  );
}

List<int> _buildMp3WithArtwork(Uint8List imageBytes) {
  final mimeBytes = ascii.encode('image/png');
  final payload = BytesBuilder(copy: false)
    ..addByte(0)
    ..add(mimeBytes)
    ..addByte(0)
    ..addByte(3)
    ..addByte(0)
    ..add(imageBytes);
  final payloadBytes = payload.toBytes();
  final frameSize = payloadBytes.length;
  final frame = BytesBuilder(copy: false)
    ..add(ascii.encode('APIC'))
    ..add(_uint32(frameSize))
    ..add(<int>[0, 0])
    ..add(payloadBytes);
  final frameBytes = frame.toBytes();
  final header = BytesBuilder(copy: false)
    ..add(ascii.encode('ID3'))
    ..add(<int>[3, 0, 0])
    ..add(_syncSafe(frameBytes.length));
  return <int>[...header.toBytes(), ...frameBytes];
}

List<int> _uint32(int value) {
  return <int>[
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];
}

List<int> _syncSafe(int value) {
  return <int>[
    (value >> 21) & 0x7f,
    (value >> 14) & 0x7f,
    (value >> 7) & 0x7f,
    value & 0x7f,
  ];
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/data/app_update_storage_service.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/data/lan_share_catalog_chunk_reassembler.dart';
import 'package:landa/features/transfer/application/transfer_path_policy.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/data/transfer_header_codec.dart';
import 'package:landa/features/transfer/domain/transfer_request.dart';
import 'package:path/path.dart' as p;

import 'test_support/test_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Security & Reliability - Happy Path and Regression Tests', () {
    test('Happy Path: ThumbnailCacheService saves and reads valid thumbnail safely', () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_thumb_happy_',
      );
      addTearDown(harness.dispose);

      final service = ThumbnailCacheService(database: harness.database);

      const validCacheId = 'cache_valid_123';
      const validThumbnailId = 'thumb_abc_456';
      final payloadBytes = Uint8List.fromList(utf8.encode('VALID_IMAGE_DATA'));

      final savedPath = await service.saveReceiverThumbnailBytes(
        ownerMacAddress: '00:11:22:33:44:55',
        cacheId: validCacheId,
        thumbnailId: validThumbnailId,
        bytes: payloadBytes,
      );

      expect(savedPath, isNotEmpty);
      expect(await File(savedPath).exists(), isTrue);
      expect(await File(savedPath).readAsBytes(), equals(payloadBytes));
    });

    test('Happy Path: TransferPathPolicy sanitizes legitimate file paths correctly', () {
      const policy = TransferPathPolicy();

      expect(policy.sanitizeRelativePath('photos/vacation/beach.jpg'), equals('photos/vacation/beach.jpg'));
      expect(policy.sanitizeRelativePath('normal_document.pdf'), equals('normal_document.pdf'));
      expect(policy.sanitizeRelativePath(''), equals('file.bin'));
    });

    test('Happy Path: TransferHeaderCodec encodes and decodes valid TransferHeader', () {
      const codec = TransferHeaderCodec();

      const original = TransferHeader(
        requestId: 'req-safe-1',
        files: [
          TransferFileManifestItem(
            fileName: 'doc.txt',
            sizeBytes: 100,
            sha256: 'deadbeef',
          ),
        ],
      );

      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded.bytes);

      expect(decoded.requestId, equals('req-safe-1'));
      expect(decoded.files.length, equals(1));
      expect(decoded.files.first.fileName, equals('doc.txt'));
      expect(decoded.files.first.sizeBytes, equals(100));
    });

    test('Happy Path: LanShareCatalogChunkReassembler reassembles normal 2-chunk catalog', () {
      final reassembler = LanShareCatalogChunkReassembler();

      final chunk0 = LanShareCatalogPacket(
        instanceId: 'inst-1',
        requestId: 'req-split-1',
        ownerName: 'Alice',
        ownerMacAddress: '00:11:22:33:44:55',
        entries: [
          SharedCatalogEntryItem(
            cacheId: 'c1',
            displayName: 'Folder1',
            itemCount: 1,
            totalBytes: 50,
            files: const [],
          ),
        ],
        removedCacheIds: const [],
        chunkIndex: 0,
        chunkCount: 2,
      );

      final chunk1 = LanShareCatalogPacket(
        instanceId: 'inst-1',
        requestId: 'req-split-1',
        ownerName: 'Alice',
        ownerMacAddress: '00:11:22:33:44:55',
        entries: [
          SharedCatalogEntryItem(
            cacheId: 'c2',
            displayName: 'Folder2',
            itemCount: 1,
            totalBytes: 50,
            files: const [],
          ),
        ],
        removedCacheIds: const [],
        chunkIndex: 1,
        chunkCount: 2,
      );

      final res0 = reassembler.consume(packet: chunk0, senderIp: '192.168.1.50');
      expect(res0, isNull); // waiting for chunk 1

      final res1 = reassembler.consume(packet: chunk1, senderIp: '192.168.1.50');
      expect(res1, isNotNull);
      expect(res1!.entries.length, equals(2));
      expect(res1.entries.map((e) => e.displayName), containsAll(['Folder1', 'Folder2']));
    });

    test('Happy Path: AppUpdateStorageService creates file in updates directory', () async {
      final mockDir = await Directory.systemTemp.createTemp('mock_dl_happy_');
      addTearDown(() => mockDir.delete(recursive: true));

      final storageService = AppUpdateStorageService(
        updateDirectoryResolver: () async => Directory(p.join(mockDir.path, 'updates')),
      );
      final targetFile = await storageService.createTargetFile('legitimate_update_v1.0.0.apk');

      expect(p.basename(targetFile.path), equals('legitimate_update_v1.0.0.apk'));
      expect(targetFile.parent.path, contains('updates'));
    });
  });
}

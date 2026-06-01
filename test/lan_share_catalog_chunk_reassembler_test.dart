import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/data/lan_share_catalog_chunk_reassembler.dart';

void main() {
  group('LanShareCatalogChunkReassembler', () {
    test('passes through non-chunked catalog packet', () {
      final reassembler = LanShareCatalogChunkReassembler();
      final packet = _catalogPacket(chunkIndex: 0, chunkCount: 1);

      expect(
        reassembler.consume(packet: packet, senderIp: '192.168.1.20'),
        same(packet),
      );
    });

    test('reassembles catalog chunks in order by chunk index', () {
      final reassembler = LanShareCatalogChunkReassembler();
      final second = _catalogPacket(
        chunkIndex: 1,
        chunkCount: 2,
        files: <SharedCatalogFileItem>[
          SharedCatalogFileItem(relativePath: 'b.txt', sizeBytes: 2),
        ],
        removedCacheIds: <String>['removed-b'],
      );
      final first = _catalogPacket(
        chunkIndex: 0,
        chunkCount: 2,
        files: <SharedCatalogFileItem>[
          SharedCatalogFileItem(relativePath: 'a.txt', sizeBytes: 1),
        ],
        removedCacheIds: <String>['removed-a'],
      );

      expect(
        reassembler.consume(packet: second, senderIp: '192.168.1.20'),
        isNull,
      );
      final merged = reassembler.consume(
        packet: first,
        senderIp: '192.168.1.20',
      );

      expect(merged, isNotNull);
      expect(merged!.entries, hasLength(1));
      expect(
        merged.entries.single.files.map((file) => file.relativePath),
        <String>['a.txt', 'b.txt'],
      );
      expect(
        merged.removedCacheIds,
        containsAll(<String>['removed-a', 'removed-b']),
      );
    });

    test('drops expired pending chunks', () {
      final now = DateTime(2026);
      final reassembler = LanShareCatalogChunkReassembler(
        chunkTtl: const Duration(seconds: 15),
      );

      expect(
        reassembler.consume(
          packet: _catalogPacket(chunkIndex: 0, chunkCount: 2),
          senderIp: '192.168.1.20',
          now: now,
        ),
        isNull,
      );
      expect(
        reassembler.consume(
          packet: _catalogPacket(chunkIndex: 1, chunkCount: 2),
          senderIp: '192.168.1.20',
          now: now.add(const Duration(seconds: 16)),
        ),
        isNull,
      );
    });
  });
}

LanShareCatalogPacket _catalogPacket({
  required int chunkIndex,
  required int chunkCount,
  List<SharedCatalogFileItem>? files,
  List<String> removedCacheIds = const <String>[],
}) {
  return LanShareCatalogPacket(
    instanceId: 'remote-instance',
    requestId: 'request-1',
    ownerName: 'Remote',
    ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
    entries: <SharedCatalogEntryItem>[
      SharedCatalogEntryItem(
        cacheId: 'cache-1',
        displayName: 'Cache',
        itemCount: 2,
        totalBytes: 3,
        files: files ?? <SharedCatalogFileItem>[],
      ),
    ],
    removedCacheIds: removedCacheIds,
    chunkIndex: chunkIndex,
    chunkCount: chunkCount,
  );
}

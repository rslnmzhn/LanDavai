import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/lan_clipboard_catalog_packet_fitter.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_share_catalog_chunk_encoder.dart';

void main() {
  late LanPacketCodec codec;
  late List<String> logs;

  setUp(() {
    codec = LanPacketCodec();
    logs = <String>[];
  });

  test('share catalog encoder chunks oversized catalogs', () {
    final encoder = LanShareCatalogChunkEncoder(
      packetCodec: codec,
      log: logs.add,
    );
    final oversizedEntries = List<SharedCatalogEntryItem>.generate(
      3,
      (entryIndex) => SharedCatalogEntryItem(
        cacheId: 'cache-$entryIndex',
        displayName: 'Entry $entryIndex',
        itemCount: 400,
        totalBytes: 1000,
        files: List<SharedCatalogFileItem>.generate(
          400,
          (fileIndex) => SharedCatalogFileItem(
            relativePath: 'project_$entryIndex/src/deep/file_$fileIndex.txt',
            sizeBytes: fileIndex + 1,
          ),
        ),
      ),
    );

    final packets = encoder.buildCatalogPackets(
      instanceId: 'instance-1',
      requestId: 'request-1',
      ownerName: 'Bob',
      ownerMacAddress: '11:22:33:44:55:66',
      entries: oversizedEntries,
      removedCacheIds: const <String>['stale-cache'],
      createdAtMs: 5678,
    );

    final chunkCounts = <int>{};
    var totalFiles = 0;
    for (final packet in packets) {
      final decoded =
          codec.decodeIncomingPacket(utf8.decode(packet.bytes))
              as LanShareCatalogPacket?;
      expect(decoded, isNotNull);
      chunkCounts.add(decoded!.chunkCount);
      totalFiles += decoded.entries.fold<int>(
        0,
        (sum, entry) => sum + entry.files.length,
      );
    }

    expect(packets.length, greaterThan(1));
    expect(chunkCounts.single, packets.length);
    expect(totalFiles, 1200);
    expect(logs, isEmpty);
  });

  test('clipboard catalog fitter trims oversized entries and logs', () {
    final fitter = LanClipboardCatalogPacketFitter(
      packetCodec: codec,
      log: logs.add,
    );
    final oversizedPreview = base64Encode(
      List<int>.filled(18 * 1024, 7, growable: false),
    );
    final oversizedEntries = List<ClipboardCatalogItem>.generate(
      3,
      (index) => ClipboardCatalogItem(
        id: 'clip-$index',
        entryType: 'image',
        createdAtMs: index + 1,
        imagePreviewBase64: oversizedPreview,
      ),
    );

    final packet = fitter.buildCatalogPacket(
      instanceId: 'instance-clipboard',
      requestId: 'request-clipboard',
      ownerName: 'Carol',
      ownerMacAddress: '22:33:44:55:66:77',
      entries: oversizedEntries,
      createdAtMs: 9999,
    );

    expect(packet, isNotNull);
    final decoded =
        codec.decodeIncomingPacket(utf8.decode(packet!.bytes))
            as LanClipboardCatalogPacket?;
    expect(decoded, isNotNull);
    expect(decoded!.entries, isNotEmpty);
    expect(decoded.entries.length, lessThan(oversizedEntries.length));
    expect(logs.single, contains('Clipboard catalog trimmed for UDP'));
  });
}

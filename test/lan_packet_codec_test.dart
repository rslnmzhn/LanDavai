import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';

void main() {
  late LanPacketCodec codec;

  setUp(() {
    codec = LanPacketCodec();
  });

  test('keeps current packet identifier family stable in codec boundary', () {
    expect(LanPacketCodec.protocolPrefixes, const <String, String>{
      'discover': 'LANDA_DISCOVER_V1',
      'response': 'LANDA_HERE_V1',
      'transferRequest': 'LANDA_TRANSFER_REQUEST_V1',
      'transferDecision': 'LANDA_TRANSFER_DECISION_V1',
      'friendRequest': 'LANDA_FRIEND_REQUEST_V1',
      'friendResponse': 'LANDA_FRIEND_RESPONSE_V1',
      'shareQuery': 'LANDA_SHARE_QUERY_V1',
      'shareAccessRequest': 'LANDA_SHARE_ACCESS_REQUEST_V1',
      'shareAccessResponse': 'LANDA_SHARE_ACCESS_RESPONSE_V1',
      'shareCatalog': 'LANDA_SHARE_CATALOG_V1',
      'downloadRequest': 'LANDA_DOWNLOAD_REQUEST_V1',
      'downloadResponse': 'LANDA_DOWNLOAD_RESPONSE_V1',
      'thumbnailSyncRequest': 'LANDA_THUMBNAIL_SYNC_REQUEST_V1',
      'thumbnailPacket': 'LANDA_THUMBNAIL_PACKET_V1',
      'clipboardQuery': 'LANDA_CLIPBOARD_QUERY_V1',
      'clipboardCatalog': 'LANDA_CLIPBOARD_CATALOG_V1',
    });
  });

  test(
    'encodes and decodes current discovery handshake payload with instance id and peer id',
    () {
      final message = codec.encodeDiscoveryRequest(
        instanceId: 'instance-1',
        deviceName: 'Workstation',
        localPeerId: 'local-peer-1',
      );
      final parsed = codec.decodeDiscoveryPacket(message);

      expect(parsed, isNotNull);
      expect(parsed!.prefix, LanPacketCodec.discoverPrefix);
      expect(parsed.instanceId, 'instance-1');
      expect(parsed.deviceName, 'Workstation');
      expect(parsed.peerId, 'local-peer-1');
      expect(parsed.operatingSystem, Platform.operatingSystem);
      expect(parsed.deviceType, _expectedDeviceType());
    },
  );

  test(
    'keeps base64url json envelope semantics for transfer share and clipboard packets',
    () {
      final transferPacket = codec.encodeTransferRequest(
        instanceId: 'instance-1',
        requestId: 'request-1',
        senderName: 'Alice',
        senderMacAddress: 'aa:bb:cc:dd:ee:ff',
        sharedCacheId: 'cache-1',
        sharedLabel: 'Docs',
        items: <TransferAnnouncementItem>[
          TransferAnnouncementItem(
            fileName: 'report.pdf',
            sizeBytes: 42,
            sha256: 'abc',
          ),
        ],
        createdAtMs: 1234,
      );
      final sharePacket = codec.encodeShareCatalog(
        instanceId: 'instance-2',
        requestId: 'request-2',
        ownerName: 'Bob',
        ownerMacAddress: '11:22:33:44:55:66',
        entries: <SharedCatalogEntryItem>[
          SharedCatalogEntryItem(
            cacheId: 'cache-2',
            displayName: 'Photos',
            itemCount: 1,
            totalBytes: 99,
            files: <SharedCatalogFileItem>[
              SharedCatalogFileItem(
                relativePath: 'photo.jpg',
                sizeBytes: 99,
                thumbnailId: 'thumb-1',
              ),
            ],
          ),
        ],
        removedCacheIds: <String>['stale-cache'],
        createdAtMs: 5678,
      );
      final clipboardPacket = codec.encodeClipboardCatalog(
        instanceId: 'instance-3',
        requestId: 'request-3',
        ownerName: 'Carol',
        ownerMacAddress: '22:33:44:55:66:77',
        entries: <ClipboardCatalogItem>[
          const ClipboardCatalogItem(
            id: 'clip-1',
            entryType: 'text',
            createdAtMs: 9999,
            textValue: 'hello',
          ),
        ],
        createdAtMs: 9999,
      );

      expect(transferPacket, isNotNull);
      expect(sharePacket, isNotNull);
      expect(clipboardPacket, isNotNull);

      final decodedTransfer = LanPacketCodec.decodeEnvelopeForTest(
        message: utf8.decode(transferPacket!.bytes),
        expectedPrefix: LanPacketCodec.transferRequestPrefix,
      );
      final decodedShare = LanPacketCodec.decodeEnvelopeForTest(
        message: utf8.decode(sharePacket!.bytes),
        expectedPrefix: LanPacketCodec.shareCatalogPrefix,
      );
      final decodedClipboard = LanPacketCodec.decodeEnvelopeForTest(
        message: utf8.decode(clipboardPacket!.bytes),
        expectedPrefix: LanPacketCodec.clipboardCatalogPrefix,
      );

      expect(decodedTransfer?['senderName'], 'Alice');
      expect(
        (decodedTransfer?['items'] as List<dynamic>).single,
        containsPair('fileName', 'report.pdf'),
      );
      expect(decodedShare?['ownerName'], 'Bob');
      expect(
        (decodedShare?['removedCacheIds'] as List<dynamic>).single,
        'stale-cache',
      );
      expect(decodedClipboard?['ownerName'], 'Carol');
      expect(
        (decodedClipboard?['entries'] as List<dynamic>).single,
        containsPair('textValue', 'hello'),
      );
    },
  );

  test(
    'encodes and decodes current share-access request and response envelopes',
    () {
      final requestPacket = codec.encodeShareAccessRequest(
        instanceId: 'instance-1',
        requestId: 'share-access-1',
        requesterName: 'Alice',
        requesterMacAddress: 'aa:bb:cc:dd:ee:ff',
        transferPort: 40404,
        createdAtMs: 1234,
      );
      final responsePacket = codec.encodeShareAccessResponse(
        instanceId: 'instance-2',
        requestId: 'share-access-1',
        responderName: 'Bob',
        approved: true,
        message: 'ok',
        createdAtMs: 5678,
      );

      expect(requestPacket, isNotNull);
      expect(responsePacket, isNotNull);

      final decodedRequest =
          codec.decodeIncomingPacket(utf8.decode(requestPacket!.bytes))
              as LanShareAccessRequestPacket?;
      final decodedResponse =
          codec.decodeIncomingPacket(utf8.decode(responsePacket!.bytes))
              as LanShareAccessResponsePacket?;

      expect(decodedRequest, isNotNull);
      expect(decodedRequest!.requesterName, 'Alice');
      expect(decodedRequest.transferPort, 40404);
      expect(decodedResponse, isNotNull);
      expect(decodedResponse!.responderName, 'Bob');
      expect(decodedResponse.approved, isTrue);
      expect(decodedResponse.message, 'ok');
    },
  );

  test('chunks oversized share catalogs into multiple UDP-safe packets', () {
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

    final packets = codec.encodeShareCatalogChunks(
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
  });

  test('fits oversized clipboard catalogs into a UDP-safe subset', () {
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

    final fitted = codec.fitClipboardCatalogEntries(
      instanceId: 'instance-clipboard',
      requestId: 'request-clipboard',
      ownerName: 'Carol',
      ownerMacAddress: '22:33:44:55:66:77',
      entries: oversizedEntries,
      createdAtMs: 9999,
    );
    final encoded = codec.encodeClipboardCatalog(
      instanceId: 'instance-clipboard',
      requestId: 'request-clipboard',
      ownerName: 'Carol',
      ownerMacAddress: '22:33:44:55:66:77',
      entries: fitted,
      createdAtMs: 9999,
    );

    expect(fitted, isNotEmpty);
    expect(fitted.length, lessThan(oversizedEntries.length));
    expect(encoded, isNotNull);
  });

  test(
    'keeps public decode rejection semantics for malformed envelopes and empty transfer payloads',
    () {
      final emptyTransferMessage = LanPacketCodec.encodeEnvelopeForTest(
        prefix: LanPacketCodec.transferRequestPrefix,
        payload: <String, Object?>{
          'instanceId': 'instance-1',
          'requestId': 'request-1',
          'senderName': 'Alice',
          'senderMacAddress': 'aa:bb:cc:dd:ee:ff',
          'sharedCacheId': 'cache-1',
          'sharedLabel': 'Docs',
          'items': const <Object?>[],
          'createdAtMs': 1234,
        },
      );

      expect(
        codec.decodeIncomingPacket('LANDA_TRANSFER_REQUEST_V1|not-base64'),
        isNull,
      );
      expect(codec.decodeIncomingPacket(emptyTransferMessage), isNull);
    },
  );

  test('keeps thumbnail decode rejection when artifact bytes decode empty', () {
    final emptyThumbnailMessage = LanPacketCodec.encodeEnvelopeForTest(
      prefix: LanPacketCodec.thumbnailPacketPrefix,
      payload: <String, Object?>{
        'instanceId': 'instance-1',
        'requestId': 'thumb-1',
        'ownerMacAddress': 'aa:bb:cc:dd:ee:ff',
        'cacheId': 'cache-1',
        'relativePath': 'image.png',
        'thumbnailId': 'thumb-1',
        'bytesBase64': '',
        'createdAtMs': 1234,
      },
    );

    expect(codec.decodeIncomingPacket(emptyThumbnailMessage), isNull);
  });
}

String _expectedDeviceType() {
  if (Platform.isAndroid || Platform.isIOS) {
    return 'phone';
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return 'pc';
  }
  return 'unknown';
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';

void main() {
  late LanPacketCodec codec;

  setUp(() {
    codec = LanPacketCodec();
  });

  test('keeps current packet identifier family stable', () {
    expect(LanPacketCodec.protocolPrefixes, const <String, String>{
      'discover': 'LANDA_DISCOVER_V1',
      'response': 'LANDA_HERE_V1',
      'transferRequest': 'LANDA_TRANSFER_REQUEST_V1',
      'transferDecision': 'LANDA_TRANSFER_DECISION_V1',
      'friendRequest': 'LANDA_FRIEND_REQUEST_V1',
      'friendResponse': 'LANDA_FRIEND_RESPONSE_V1',
      'shareQuery': 'LANDA_SHARE_QUERY_V1',
      'shareCatalog': 'LANDA_SHARE_CATALOG_V1',
      'downloadRequest': 'LANDA_DOWNLOAD_REQUEST_V1',
      'thumbnailSyncRequest': 'LANDA_THUMBNAIL_SYNC_REQUEST_V1',
      'thumbnailPacket': 'LANDA_THUMBNAIL_PACKET_V1',
      'clipboardQuery': 'LANDA_CLIPBOARD_QUERY_V1',
      'clipboardCatalog': 'LANDA_CLIPBOARD_CATALOG_V1',
    });
  });

  test(
    'builds and parses current discovery handshake payload with instance id and peer id',
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
      expect(parsed.instanceId, isNot('legacy'));
      expect(parsed.deviceName, 'Workstation');
      expect(parsed.peerId, 'local-peer-1');
      expect(parsed.operatingSystem, Platform.operatingSystem);
      expect(parsed.deviceType, _expectedDeviceType());
    },
  );

  test('keeps backward-compatible legacy discovery packet parsing', () {
    final parsed = codec.decodeDiscoveryPacket(
      'LANDA_HERE_V1|Legacy workstation',
    );

    expect(parsed, isNotNull);
    expect(parsed!.prefix, 'LANDA_HERE_V1');
    expect(parsed.instanceId, 'legacy');
    expect(parsed.deviceName, 'Legacy workstation');
    expect(parsed.peerId, isNull);
  });

  test(
    'keeps discovery fallback parsing when the payload segment is not base64url json',
    () {
      final parsed = codec.decodeDiscoveryPacket(
        'LANDA_HERE_V1|instance-2|Legacy payload name',
      );

      expect(parsed, isNotNull);
      expect(parsed!.prefix, LanPacketCodec.responsePrefix);
      expect(parsed.instanceId, 'instance-2');
      expect(parsed.deviceName, 'Legacy payload name');
      expect(parsed.peerId, isNull);
      expect(parsed.operatingSystem, isNull);
      expect(parsed.deviceType, isNull);
    },
  );

  test(
    'keeps base64url json envelope semantics for transfer, share, and clipboard packets',
    () {
      final prefixes = LanPacketCodec.protocolPrefixes;
      final transferMessage = LanPacketCodec.encodeEnvelopeForTest(
        prefix: prefixes['transferRequest']!,
        payload: <String, Object?>{
          'instanceId': 'instance-1',
          'requestId': 'request-1',
          'senderName': 'Alice',
          'senderMacAddress': 'aa:bb:cc:dd:ee:ff',
          'sharedCacheId': 'cache-1',
          'sharedLabel': 'Docs',
          'items': <Map<String, Object>>[
            TransferAnnouncementItem(
              fileName: 'report.pdf',
              sizeBytes: 42,
              sha256: 'abc',
            ).toJson(),
          ],
          'createdAtMs': 1234,
        },
      );
      final shareMessage = LanPacketCodec.encodeEnvelopeForTest(
        prefix: prefixes['shareCatalog']!,
        payload: <String, Object?>{
          'instanceId': 'instance-2',
          'requestId': 'request-2',
          'ownerName': 'Bob',
          'ownerMacAddress': '11:22:33:44:55:66',
          'entries': <Map<String, Object>>[
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
            ).toJson(),
          ],
          'removedCacheIds': <String>['stale-cache'],
          'createdAtMs': 5678,
        },
      );
      final clipboardMessage = LanPacketCodec.encodeEnvelopeForTest(
        prefix: prefixes['clipboardCatalog']!,
        payload: <String, Object?>{
          'instanceId': 'instance-3',
          'requestId': 'request-3',
          'ownerName': 'Carol',
          'ownerMacAddress': '22:33:44:55:66:77',
          'entries': <Map<String, Object?>>[
            const ClipboardCatalogItem(
              id: 'clip-1',
              entryType: 'text',
              createdAtMs: 9999,
              textValue: 'hello',
            ).toJson(),
          ],
          'createdAtMs': 9999,
        },
      );

      final decodedTransfer = LanPacketCodec.decodeEnvelopeForTest(
        message: transferMessage,
        expectedPrefix: prefixes['transferRequest']!,
      );
      final decodedShare = LanPacketCodec.decodeEnvelopeForTest(
        message: shareMessage,
        expectedPrefix: prefixes['shareCatalog']!,
      );
      final decodedClipboard = LanPacketCodec.decodeEnvelopeForTest(
        message: clipboardMessage,
        expectedPrefix: prefixes['clipboardCatalog']!,
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
      expect(
        LanPacketCodec.decodeEnvelopeForTest(
          message: transferMessage,
          expectedPrefix: prefixes['transferDecision']!,
        ),
        isNull,
      );
      expect(
        LanPacketCodec.decodeEnvelopeForTest(
          message: 'LANDA_TRANSFER_REQUEST_V1|not-base64',
          expectedPrefix: prefixes['transferRequest']!,
        ),
        isNull,
      );
    },
  );

  test('trims share catalog entries with current UDP packet limits', () {
    final oversizedEntries = List<SharedCatalogEntryItem>.generate(
      70,
      (entryIndex) => SharedCatalogEntryItem(
        cacheId: 'cache-$entryIndex',
        displayName: 'Entry $entryIndex',
        itemCount: 100,
        totalBytes: 1000,
        files: List<SharedCatalogFileItem>.generate(
          100,
          (fileIndex) => SharedCatalogFileItem(
            relativePath: 'file_${entryIndex}_$fileIndex.txt',
            sizeBytes: fileIndex + 1,
          ),
        ),
      ),
    );

    final fitted = codec.fitShareCatalogEntries(oversizedEntries);
    final totalFiles = fitted.fold<int>(
      0,
      (sum, entry) => sum + entry.files.length,
    );

    expect(fitted.length, 64);
    expect(fitted.every((entry) => entry.files.length <= 80), isTrue);
    expect(totalFiles, 240);
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

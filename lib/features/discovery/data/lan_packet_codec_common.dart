import 'dart:convert';
import 'dart:typed_data';

import 'lan_packet_codec_models.dart';

const int lanMaxUdpPacketBytes = 60 * 1024;
const int lanMaxShareCatalogEntriesPerPacket = 64;
const int lanMaxShareCatalogFilesPerPacket = 240;
const int lanMaxShareCatalogFilesPerEntry = 80;

const String lanDiscoverPrefix = 'LANDA_DISCOVER_V1';
const String lanResponsePrefix = 'LANDA_HERE_V1';
const String lanTransferRequestPrefix = 'LANDA_TRANSFER_REQUEST_V1';
const String lanTransferDecisionPrefix = 'LANDA_TRANSFER_DECISION_V1';
const String lanFriendRequestPrefix = 'LANDA_FRIEND_REQUEST_V1';
const String lanFriendResponsePrefix = 'LANDA_FRIEND_RESPONSE_V1';
const String lanShareQueryPrefix = 'LANDA_SHARE_QUERY_V1';
const String lanShareCatalogPrefix = 'LANDA_SHARE_CATALOG_V1';
const String lanDownloadRequestPrefix = 'LANDA_DOWNLOAD_REQUEST_V1';
const String lanThumbnailSyncRequestPrefix = 'LANDA_THUMBNAIL_SYNC_REQUEST_V1';
const String lanThumbnailPacketPrefix = 'LANDA_THUMBNAIL_PACKET_V1';
const String lanClipboardQueryPrefix = 'LANDA_CLIPBOARD_QUERY_V1';
const String lanClipboardCatalogPrefix = 'LANDA_CLIPBOARD_CATALOG_V1';

const Map<String, String> lanProtocolPrefixes = <String, String>{
  'discover': lanDiscoverPrefix,
  'response': lanResponsePrefix,
  'transferRequest': lanTransferRequestPrefix,
  'transferDecision': lanTransferDecisionPrefix,
  'friendRequest': lanFriendRequestPrefix,
  'friendResponse': lanFriendResponsePrefix,
  'shareQuery': lanShareQueryPrefix,
  'shareCatalog': lanShareCatalogPrefix,
  'downloadRequest': lanDownloadRequestPrefix,
  'thumbnailSyncRequest': lanThumbnailSyncRequestPrefix,
  'thumbnailPacket': lanThumbnailPacketPrefix,
  'clipboardQuery': lanClipboardQueryPrefix,
  'clipboardCatalog': lanClipboardCatalogPrefix,
};

String encodeLanEnvelopeForTest({
  required String prefix,
  required Map<String, Object?> payload,
}) {
  final encodedPayload = base64UrlEncode(utf8.encode(jsonEncode(payload)));
  return '$prefix|$encodedPayload';
}

Map<String, dynamic>? decodeLanEnvelope({
  required String message,
  required String expectedPrefix,
}) {
  final splitIndex = message.indexOf('|');
  if (splitIndex <= 0 || splitIndex >= message.length - 1) {
    return null;
  }

  final prefix = message.substring(0, splitIndex).trim();
  if (prefix != expectedPrefix) {
    return null;
  }

  final encodedPayload = message.substring(splitIndex + 1).trim();
  try {
    final bytes = base64Url.decode(encodedPayload);
    final json = jsonDecode(utf8.decode(bytes));
    if (json is Map<String, dynamic>) {
      return json;
    }
  } catch (_) {
    return null;
  }
  return null;
}

EncodedLanPacket? encodeLanEnvelopePacket({
  required String prefix,
  required Map<String, Object?> payload,
}) {
  final message = encodeLanEnvelopeForTest(prefix: prefix, payload: payload);
  final messageBytes = utf8.encode(message);
  if (messageBytes.length > lanMaxUdpPacketBytes) {
    return null;
  }
  return EncodedLanPacket(
    prefix: prefix,
    bytes: Uint8List.fromList(messageBytes),
  );
}

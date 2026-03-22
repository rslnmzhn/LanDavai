part of 'lan_discovery_service.dart';

class EncodedLanPacket {
  const EncodedLanPacket({required this.prefix, required this.bytes});

  final String prefix;
  final Uint8List bytes;
}

abstract class LanInboundPacket {
  const LanInboundPacket({required this.instanceId});

  final String instanceId;
}

class LanDiscoveryPresencePacket extends LanInboundPacket {
  const LanDiscoveryPresencePacket({
    required this.prefix,
    required super.instanceId,
    required this.deviceName,
    this.operatingSystem,
    this.deviceType,
    this.peerId,
  });

  final String prefix;
  final String deviceName;
  final String? operatingSystem;
  final String? deviceType;
  final String? peerId;
}

class LanTransferRequestPacket extends LanInboundPacket {
  const LanTransferRequestPacket({
    required super.instanceId,
    required this.requestId,
    required this.senderName,
    required this.senderMacAddress,
    required this.sharedCacheId,
    required this.sharedLabel,
    required this.items,
  });

  final String requestId;
  final String senderName;
  final String senderMacAddress;
  final String sharedCacheId;
  final String sharedLabel;
  final List<TransferAnnouncementItem> items;
}

class LanTransferDecisionPacket extends LanInboundPacket {
  const LanTransferDecisionPacket({
    required super.instanceId,
    required this.requestId,
    required this.receiverName,
    required this.approved,
    required this.transferPort,
    this.acceptedFileNames,
  });

  final String requestId;
  final String receiverName;
  final bool approved;
  final int? transferPort;
  final List<String>? acceptedFileNames;
}

class LanFriendRequestPacket extends LanInboundPacket {
  const LanFriendRequestPacket({
    required super.instanceId,
    required this.requestId,
    required this.requesterName,
    required this.requesterMacAddress,
  });

  final String requestId;
  final String requesterName;
  final String requesterMacAddress;
}

class LanFriendResponsePacket extends LanInboundPacket {
  const LanFriendResponsePacket({
    required super.instanceId,
    required this.requestId,
    required this.responderName,
    required this.responderMacAddress,
    required this.accepted,
  });

  final String requestId;
  final String responderName;
  final String responderMacAddress;
  final bool accepted;
}

class LanShareQueryPacket extends LanInboundPacket {
  const LanShareQueryPacket({
    required super.instanceId,
    required this.requestId,
    required this.requesterName,
  });

  final String requestId;
  final String requesterName;
}

class LanShareCatalogPacket extends LanInboundPacket {
  const LanShareCatalogPacket({
    required super.instanceId,
    required this.requestId,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
    required this.removedCacheIds,
  });

  final String requestId;
  final String ownerName;
  final String ownerMacAddress;
  final List<SharedCatalogEntryItem> entries;
  final List<String> removedCacheIds;
}

class LanDownloadRequestPacket extends LanInboundPacket {
  const LanDownloadRequestPacket({
    required super.instanceId,
    required this.requestId,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.cacheId,
    required this.selectedRelativePaths,
    required this.previewMode,
  });

  final String requestId;
  final String requesterName;
  final String requesterMacAddress;
  final String cacheId;
  final List<String> selectedRelativePaths;
  final bool previewMode;
}

class LanThumbnailSyncRequestPacket extends LanInboundPacket {
  const LanThumbnailSyncRequestPacket({
    required super.instanceId,
    required this.requestId,
    required this.requesterName,
    required this.items,
  });

  final String requestId;
  final String requesterName;
  final List<ThumbnailSyncItem> items;
}

class LanThumbnailPacket extends LanInboundPacket {
  const LanThumbnailPacket({
    required super.instanceId,
    required this.requestId,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
    required this.bytes,
  });

  final String requestId;
  final String ownerMacAddress;
  final String cacheId;
  final String relativePath;
  final String thumbnailId;
  final Uint8List bytes;
}

class LanClipboardQueryPacket extends LanInboundPacket {
  const LanClipboardQueryPacket({
    required super.instanceId,
    required this.requestId,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.maxEntries,
  });

  final String requestId;
  final String requesterName;
  final String requesterMacAddress;
  final int maxEntries;
}

class LanClipboardCatalogPacket extends LanInboundPacket {
  const LanClipboardCatalogPacket({
    required super.instanceId,
    required this.requestId,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
  });

  final String requestId;
  final String ownerName;
  final String ownerMacAddress;
  final List<ClipboardCatalogItem> entries;
}

class LanPacketCodec {
  static const int _maxUdpPacketBytes = 60 * 1024;
  static const int _maxShareCatalogEntriesPerPacket = 64;
  static const int _maxShareCatalogFilesPerPacket = 240;
  static const int _maxShareCatalogFilesPerEntry = 80;

  static const String discoverPrefix = 'LANDA_DISCOVER_V1';
  static const String responsePrefix = 'LANDA_HERE_V1';
  static const String transferRequestPrefix = 'LANDA_TRANSFER_REQUEST_V1';
  static const String transferDecisionPrefix = 'LANDA_TRANSFER_DECISION_V1';
  static const String friendRequestPrefix = 'LANDA_FRIEND_REQUEST_V1';
  static const String friendResponsePrefix = 'LANDA_FRIEND_RESPONSE_V1';
  static const String shareQueryPrefix = 'LANDA_SHARE_QUERY_V1';
  static const String shareCatalogPrefix = 'LANDA_SHARE_CATALOG_V1';
  static const String downloadRequestPrefix = 'LANDA_DOWNLOAD_REQUEST_V1';
  static const String thumbnailSyncRequestPrefix =
      'LANDA_THUMBNAIL_SYNC_REQUEST_V1';
  static const String thumbnailPacketPrefix = 'LANDA_THUMBNAIL_PACKET_V1';
  static const String clipboardQueryPrefix = 'LANDA_CLIPBOARD_QUERY_V1';
  static const String clipboardCatalogPrefix = 'LANDA_CLIPBOARD_CATALOG_V1';

  static const Map<String, String> protocolPrefixes = <String, String>{
    'discover': discoverPrefix,
    'response': responsePrefix,
    'transferRequest': transferRequestPrefix,
    'transferDecision': transferDecisionPrefix,
    'friendRequest': friendRequestPrefix,
    'friendResponse': friendResponsePrefix,
    'shareQuery': shareQueryPrefix,
    'shareCatalog': shareCatalogPrefix,
    'downloadRequest': downloadRequestPrefix,
    'thumbnailSyncRequest': thumbnailSyncRequestPrefix,
    'thumbnailPacket': thumbnailPacketPrefix,
    'clipboardQuery': clipboardQueryPrefix,
    'clipboardCatalog': clipboardCatalogPrefix,
  };

  LanPacketCodec({String? operatingSystem, String? deviceType})
    : _operatingSystem = operatingSystem ?? Platform.operatingSystem,
      _deviceType = deviceType ?? _resolveLocalDeviceType();

  final String _operatingSystem;
  final String _deviceType;

  String encodeDiscoveryRequest({
    required String instanceId,
    required String deviceName,
    required String localPeerId,
  }) {
    return _encodeDiscoveryPacket(
      prefix: discoverPrefix,
      instanceId: instanceId,
      deviceName: deviceName,
      localPeerId: localPeerId,
    );
  }

  String encodeDiscoveryResponse({
    required String instanceId,
    required String deviceName,
    required String localPeerId,
  }) {
    return _encodeDiscoveryPacket(
      prefix: responsePrefix,
      instanceId: instanceId,
      deviceName: deviceName,
      localPeerId: localPeerId,
    );
  }

  LanDiscoveryPresencePacket? decodeDiscoveryPacket(String message) {
    final parts = message.split('|');
    if (parts.isEmpty) {
      return null;
    }

    final prefix = parts[0].trim();
    if (prefix != discoverPrefix && prefix != responsePrefix) {
      return null;
    }

    if (parts.length == 2) {
      final legacyName = parts[1].trim();
      return LanDiscoveryPresencePacket(
        prefix: prefix,
        instanceId: 'legacy',
        deviceName: legacyName.isEmpty ? 'Unknown device' : legacyName,
      );
    }

    if (parts.length >= 3) {
      final instanceId = parts[1].trim();
      final rawPayload = parts.sublist(2).join('|').trim();
      final decodedPayload = _tryDecodeDiscoveryPayload(rawPayload);
      if (decodedPayload != null) {
        return LanDiscoveryPresencePacket(
          prefix: prefix,
          instanceId: instanceId,
          deviceName: decodedPayload.deviceName,
          operatingSystem: decodedPayload.operatingSystem,
          deviceType: decodedPayload.deviceType,
          peerId: decodedPayload.peerId,
        );
      }

      return LanDiscoveryPresencePacket(
        prefix: prefix,
        instanceId: instanceId,
        deviceName: rawPayload.isEmpty ? 'Unknown device' : rawPayload,
      );
    }

    return null;
  }

  LanInboundPacket? decodeIncomingPacket(String message) {
    final discoveryPacket = decodeDiscoveryPacket(message);
    if (discoveryPacket != null) {
      return discoveryPacket;
    }

    final splitIndex = message.indexOf('|');
    if (splitIndex <= 0) {
      return null;
    }

    final prefix = message.substring(0, splitIndex).trim();
    switch (prefix) {
      case transferRequestPrefix:
        return _parseTransferRequestPacket(message);
      case transferDecisionPrefix:
        return _parseTransferDecisionPacket(message);
      case friendRequestPrefix:
        return _parseFriendRequestPacket(message);
      case friendResponsePrefix:
        return _parseFriendResponsePacket(message);
      case shareQueryPrefix:
        return _parseShareQueryPacket(message);
      case shareCatalogPrefix:
        return _parseShareCatalogPacket(message);
      case downloadRequestPrefix:
        return _parseDownloadRequestPacket(message);
      case thumbnailSyncRequestPrefix:
        return _parseThumbnailSyncRequestPacket(message);
      case thumbnailPacketPrefix:
        return _parseThumbnailPacket(message);
      case clipboardQueryPrefix:
        return _parseClipboardQueryPacket(message);
      case clipboardCatalogPrefix:
        return _parseClipboardCatalogPacket(message);
    }

    return null;
  }

  EncodedLanPacket? encodeTransferRequest({
    required String instanceId,
    required String requestId,
    required String senderName,
    required String senderMacAddress,
    required String sharedCacheId,
    required String sharedLabel,
    required List<TransferAnnouncementItem> items,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'senderName': senderName,
      'senderMacAddress': senderMacAddress,
      'sharedCacheId': sharedCacheId,
      'sharedLabel': sharedLabel,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'createdAtMs': createdAtMs,
    };
    return _encodeEnvelopePacket(
      prefix: transferRequestPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeTransferDecision({
    required String instanceId,
    required String requestId,
    required bool approved,
    required String receiverName,
    required int createdAtMs,
    int? transferPort,
    List<String>? acceptedFileNames,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'approved': approved,
      'receiverName': receiverName,
      'createdAtMs': createdAtMs,
    };
    if (transferPort != null) {
      payload['transferPort'] = transferPort;
    }
    if (acceptedFileNames != null) {
      payload['acceptedFileNames'] = acceptedFileNames;
    }
    return _encodeEnvelopePacket(
      prefix: transferDecisionPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeFriendRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'requesterMacAddress': requesterMacAddress,
      'createdAtMs': createdAtMs,
    };
    return _encodeEnvelopePacket(prefix: friendRequestPrefix, payload: payload);
  }

  EncodedLanPacket? encodeFriendResponse({
    required String instanceId,
    required String requestId,
    required String responderName,
    required String responderMacAddress,
    required bool accepted,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'responderName': responderName,
      'responderMacAddress': responderMacAddress,
      'accepted': accepted,
      'createdAtMs': createdAtMs,
    };
    return _encodeEnvelopePacket(
      prefix: friendResponsePrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeShareQuery({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'createdAtMs': createdAtMs,
    };
    return _encodeEnvelopePacket(prefix: shareQueryPrefix, payload: payload);
  }

  EncodedLanPacket? encodeShareCatalog({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    required List<String> removedCacheIds,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'ownerName': ownerName,
      'ownerMacAddress': ownerMacAddress,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'removedCacheIds': removedCacheIds,
      'createdAtMs': createdAtMs,
    };
    return _encodeEnvelopePacket(prefix: shareCatalogPrefix, payload: payload);
  }

  EncodedLanPacket? encodeDownloadRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required String cacheId,
    required List<String> selectedRelativePaths,
    required bool previewMode,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'requesterMacAddress': requesterMacAddress,
      'cacheId': cacheId,
      'selectedRelativePaths': selectedRelativePaths,
      'previewMode': previewMode,
      'createdAtMs': createdAtMs,
    };
    return _encodeEnvelopePacket(
      prefix: downloadRequestPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeThumbnailSyncRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required List<ThumbnailSyncItem> items,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'createdAtMs': createdAtMs,
    };
    return _encodeEnvelopePacket(
      prefix: thumbnailSyncRequestPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeThumbnailPacket({
    required String instanceId,
    required String requestId,
    required String ownerMacAddress,
    required String cacheId,
    required String relativePath,
    required String thumbnailId,
    required Uint8List bytes,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'ownerMacAddress': ownerMacAddress,
      'cacheId': cacheId,
      'relativePath': relativePath,
      'thumbnailId': thumbnailId,
      'bytesBase64': base64Encode(bytes),
      'createdAtMs': createdAtMs,
    };
    return _encodeEnvelopePacket(
      prefix: thumbnailPacketPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeClipboardQuery({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int maxEntries,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'requesterMacAddress': requesterMacAddress,
      'maxEntries': maxEntries,
      'createdAtMs': createdAtMs,
    };
    return _encodeEnvelopePacket(
      prefix: clipboardQueryPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeClipboardCatalog({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<ClipboardCatalogItem> entries,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'ownerName': ownerName,
      'ownerMacAddress': ownerMacAddress,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'createdAtMs': createdAtMs,
    };
    return _encodeEnvelopePacket(
      prefix: clipboardCatalogPrefix,
      payload: payload,
    );
  }

  List<SharedCatalogEntryItem> fitShareCatalogEntries(
    List<SharedCatalogEntryItem> entries,
  ) {
    if (entries.isEmpty) {
      return const <SharedCatalogEntryItem>[];
    }

    final limited = <SharedCatalogEntryItem>[];
    var remainingFilesBudget = _maxShareCatalogFilesPerPacket;
    final entryLimit = min(entries.length, _maxShareCatalogEntriesPerPacket);

    for (var i = 0; i < entryLimit; i += 1) {
      final entry = entries[i];
      final perEntryBudget = min(
        _maxShareCatalogFilesPerEntry,
        max(0, remainingFilesBudget),
      );
      final keepFilesCount = min(entry.files.length, perEntryBudget);
      final keptFiles = keepFilesCount == entry.files.length
          ? entry.files
          : entry.files.take(keepFilesCount).toList(growable: false);
      remainingFilesBudget -= keepFilesCount;
      limited.add(
        SharedCatalogEntryItem(
          cacheId: entry.cacheId,
          displayName: entry.displayName,
          itemCount: entry.itemCount,
          totalBytes: entry.totalBytes,
          files: keptFiles,
        ),
      );
    }

    return limited;
  }

  static String encodeEnvelopeForTest({
    required String prefix,
    required Map<String, Object?> payload,
  }) {
    final encodedPayload = base64UrlEncode(utf8.encode(jsonEncode(payload)));
    return '$prefix|$encodedPayload';
  }

  static Map<String, dynamic>? decodeEnvelopeForTest({
    required String message,
    required String expectedPrefix,
  }) {
    return LanPacketCodec()._decodeEnvelope(
      message: message,
      expectedPrefix: expectedPrefix,
    );
  }

  String _encodeDiscoveryPacket({
    required String prefix,
    required String instanceId,
    required String deviceName,
    required String localPeerId,
  }) {
    final payload = <String, Object>{
      'name': deviceName,
      'os': _operatingSystem,
      'type': _deviceType,
      'peerId': localPeerId,
    };
    final encodedPayload = base64UrlEncode(utf8.encode(jsonEncode(payload)));
    return '$prefix|$instanceId|$encodedPayload';
  }

  EncodedLanPacket? _encodeEnvelopePacket({
    required String prefix,
    required Map<String, Object?> payload,
  }) {
    final message = encodeEnvelopeForTest(prefix: prefix, payload: payload);
    final messageBytes = utf8.encode(message);
    if (messageBytes.length > _maxUdpPacketBytes) {
      return null;
    }
    return EncodedLanPacket(
      prefix: prefix,
      bytes: Uint8List.fromList(messageBytes),
    );
  }

  _DiscoveryIdentity? _tryDecodeDiscoveryPayload(String encodedPayload) {
    if (encodedPayload.isEmpty) {
      return null;
    }
    try {
      final bytes = base64Url.decode(encodedPayload);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final rawName = decoded['name'] as String?;
      final rawOs = decoded['os'] as String?;
      final rawType = decoded['type'] as String?;
      final rawPeerId = decoded['peerId'] as String?;
      return _DiscoveryIdentity(
        deviceName: (rawName == null || rawName.trim().isEmpty)
            ? 'Unknown device'
            : rawName.trim(),
        operatingSystem: _normalizeDiscoveryText(rawOs),
        deviceType: _normalizeDiscoveryText(rawType),
        peerId: _normalizeDiscoveryText(rawPeerId),
      );
    } catch (_) {
      return null;
    }
  }

  String? _normalizeDiscoveryText(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static String _resolveLocalDeviceType() {
    if (Platform.isAndroid || Platform.isIOS) {
      return 'phone';
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return 'pc';
    }
    return 'unknown';
  }

  LanTransferRequestPacket? _parseTransferRequestPacket(String message) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: transferRequestPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final requestId = decoded['requestId'] as String?;
    final senderName = decoded['senderName'] as String?;
    final senderMacAddress = decoded['senderMacAddress'] as String?;
    final sharedCacheId = decoded['sharedCacheId'] as String?;
    final sharedLabel = decoded['sharedLabel'] as String?;
    final instanceId = decoded['instanceId'] as String?;
    final itemsRaw = decoded['items'];
    if (requestId == null ||
        senderName == null ||
        senderMacAddress == null ||
        sharedCacheId == null ||
        sharedLabel == null ||
        instanceId == null ||
        itemsRaw is! List<dynamic>) {
      return null;
    }

    final items = <TransferAnnouncementItem>[];
    for (final item in itemsRaw) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final parsed = TransferAnnouncementItem.fromJson(item);
      if (parsed != null) {
        items.add(parsed);
      }
    }
    if (items.isEmpty) {
      return null;
    }

    return LanTransferRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      senderName: senderName,
      senderMacAddress: senderMacAddress,
      sharedCacheId: sharedCacheId,
      sharedLabel: sharedLabel,
      items: items,
    );
  }

  LanTransferDecisionPacket? _parseTransferDecisionPacket(String message) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: transferDecisionPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final requestId = decoded['requestId'] as String?;
    final receiverName = decoded['receiverName'] as String?;
    final approved = decoded['approved'] as bool?;
    final instanceId = decoded['instanceId'] as String?;
    final transferPortRaw = decoded['transferPort'];
    int? transferPort;
    if (transferPortRaw is num) {
      transferPort = transferPortRaw.toInt();
    }
    List<String>? acceptedFileNames;
    final acceptedRaw = decoded['acceptedFileNames'];
    if (acceptedRaw is List<dynamic>) {
      acceptedFileNames = acceptedRaw
          .whereType<String>()
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
    }
    if (requestId == null ||
        receiverName == null ||
        approved == null ||
        instanceId == null) {
      return null;
    }

    return LanTransferDecisionPacket(
      instanceId: instanceId,
      requestId: requestId,
      receiverName: receiverName,
      approved: approved,
      transferPort: transferPort,
      acceptedFileNames: acceptedFileNames,
    );
  }

  LanFriendRequestPacket? _parseFriendRequestPacket(String message) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: friendRequestPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    final requesterMacAddress = decoded['requesterMacAddress'] as String?;
    if (instanceId == null ||
        requestId == null ||
        requesterName == null ||
        requesterMacAddress == null) {
      return null;
    }

    return LanFriendRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
    );
  }

  LanFriendResponsePacket? _parseFriendResponsePacket(String message) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: friendResponsePrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final responderName = decoded['responderName'] as String?;
    final responderMacAddress = decoded['responderMacAddress'] as String?;
    final accepted = decoded['accepted'] as bool?;
    if (instanceId == null ||
        requestId == null ||
        responderName == null ||
        responderMacAddress == null ||
        accepted == null) {
      return null;
    }

    return LanFriendResponsePacket(
      instanceId: instanceId,
      requestId: requestId,
      responderName: responderName,
      responderMacAddress: responderMacAddress,
      accepted: accepted,
    );
  }

  LanShareQueryPacket? _parseShareQueryPacket(String message) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: shareQueryPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    if (instanceId == null || requestId == null || requesterName == null) {
      return null;
    }

    return LanShareQueryPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
    );
  }

  LanShareCatalogPacket? _parseShareCatalogPacket(String message) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: shareCatalogPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final ownerName = decoded['ownerName'] as String?;
    final ownerMacAddress = decoded['ownerMacAddress'] as String?;
    final entriesRaw = decoded['entries'];
    if (instanceId == null ||
        requestId == null ||
        ownerName == null ||
        ownerMacAddress == null ||
        entriesRaw is! List<dynamic>) {
      return null;
    }

    final entries = <SharedCatalogEntryItem>[];
    for (final rawEntry in entriesRaw) {
      if (rawEntry is! Map<String, dynamic>) {
        continue;
      }
      final parsed = SharedCatalogEntryItem.fromJson(rawEntry);
      if (parsed != null) {
        entries.add(parsed);
      }
    }

    final removedRaw = decoded['removedCacheIds'];
    final removedCacheIds = <String>[];
    if (removedRaw is List<dynamic>) {
      for (final raw in removedRaw) {
        if (raw is! String) {
          continue;
        }
        final normalized = raw.trim();
        if (normalized.isEmpty) {
          continue;
        }
        removedCacheIds.add(normalized);
      }
    }

    return LanShareCatalogPacket(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      removedCacheIds: removedCacheIds,
    );
  }

  LanDownloadRequestPacket? _parseDownloadRequestPacket(String message) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: downloadRequestPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    final requesterMacAddress = decoded['requesterMacAddress'] as String?;
    final cacheId = decoded['cacheId'] as String?;
    final selectedRelativePathsRaw = decoded['selectedRelativePaths'];
    final previewMode = decoded['previewMode'] as bool? ?? false;
    if (instanceId == null ||
        requestId == null ||
        requesterName == null ||
        requesterMacAddress == null ||
        cacheId == null) {
      return null;
    }

    final selectedRelativePaths = <String>[];
    if (selectedRelativePathsRaw is List<dynamic>) {
      for (final raw in selectedRelativePathsRaw) {
        if (raw is! String) {
          continue;
        }
        final normalized = raw.trim();
        if (normalized.isEmpty) {
          continue;
        }
        selectedRelativePaths.add(normalized);
      }
    }

    return LanDownloadRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      cacheId: cacheId,
      selectedRelativePaths: selectedRelativePaths,
      previewMode: previewMode,
    );
  }

  LanThumbnailSyncRequestPacket? _parseThumbnailSyncRequestPacket(
    String message,
  ) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: thumbnailSyncRequestPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    final itemsRaw = decoded['items'];
    if (instanceId == null ||
        requestId == null ||
        requesterName == null ||
        itemsRaw is! List<dynamic>) {
      return null;
    }

    final items = <ThumbnailSyncItem>[];
    for (final raw in itemsRaw) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final parsed = ThumbnailSyncItem.fromJson(raw);
      if (parsed != null) {
        items.add(parsed);
      }
    }
    if (items.isEmpty) {
      return null;
    }

    return LanThumbnailSyncRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      items: items,
    );
  }

  LanThumbnailPacket? _parseThumbnailPacket(String message) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: thumbnailPacketPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final ownerMacAddress = decoded['ownerMacAddress'] as String?;
    final cacheId = decoded['cacheId'] as String?;
    final relativePath = decoded['relativePath'] as String?;
    final thumbnailId = decoded['thumbnailId'] as String?;
    final bytesBase64 = decoded['bytesBase64'] as String?;
    if (instanceId == null ||
        requestId == null ||
        ownerMacAddress == null ||
        cacheId == null ||
        relativePath == null ||
        thumbnailId == null ||
        bytesBase64 == null) {
      return null;
    }

    try {
      final bytes = base64Decode(bytesBase64);
      if (bytes.isEmpty) {
        return null;
      }
      return LanThumbnailPacket(
        instanceId: instanceId,
        requestId: requestId,
        ownerMacAddress: ownerMacAddress,
        cacheId: cacheId,
        relativePath: relativePath,
        thumbnailId: thumbnailId,
        bytes: Uint8List.fromList(bytes),
      );
    } catch (_) {
      return null;
    }
  }

  LanClipboardQueryPacket? _parseClipboardQueryPacket(String message) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: clipboardQueryPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    final requesterMacAddress = decoded['requesterMacAddress'] as String?;
    final maxEntriesRaw = decoded['maxEntries'];
    if (instanceId == null ||
        requestId == null ||
        requesterName == null ||
        requesterMacAddress == null ||
        maxEntriesRaw is! num) {
      return null;
    }

    return LanClipboardQueryPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      maxEntries: maxEntriesRaw.toInt(),
    );
  }

  LanClipboardCatalogPacket? _parseClipboardCatalogPacket(String message) {
    final decoded = _decodeEnvelope(
      message: message,
      expectedPrefix: clipboardCatalogPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final ownerName = decoded['ownerName'] as String?;
    final ownerMacAddress = decoded['ownerMacAddress'] as String?;
    final entriesRaw = decoded['entries'];
    if (instanceId == null ||
        requestId == null ||
        ownerName == null ||
        ownerMacAddress == null ||
        entriesRaw is! List<dynamic>) {
      return null;
    }

    final entries = <ClipboardCatalogItem>[];
    for (final rawEntry in entriesRaw) {
      if (rawEntry is! Map<String, dynamic>) {
        continue;
      }
      final parsed = ClipboardCatalogItem.fromJson(rawEntry);
      if (parsed != null) {
        entries.add(parsed);
      }
    }

    return LanClipboardCatalogPacket(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
    );
  }

  Map<String, dynamic>? _decodeEnvelope({
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
}

class _DiscoveryIdentity {
  const _DiscoveryIdentity({
    required this.deviceName,
    this.operatingSystem,
    this.deviceType,
    this.peerId,
  });

  final String deviceName;
  final String? operatingSystem;
  final String? deviceType;
  final String? peerId;
}

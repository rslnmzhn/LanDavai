import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

class AppPresenceEvent {
  AppPresenceEvent({
    required this.ip,
    required this.deviceName,
    required this.observedAt,
    this.operatingSystem,
    this.deviceType,
  });

  final String ip;
  final String deviceName;
  final DateTime observedAt;
  final String? operatingSystem;
  final String? deviceType;
}

class TransferAnnouncementItem {
  TransferAnnouncementItem({
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
  });

  final String fileName;
  final int sizeBytes;
  final String sha256;

  Map<String, Object> toJson() {
    return <String, Object>{
      'fileName': fileName,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
    };
  }

  static TransferAnnouncementItem? fromJson(Map<String, dynamic> json) {
    final fileName = json['fileName'] as String?;
    final sizeRaw = json['sizeBytes'];
    final sha256 = json['sha256'] as String?;
    if (fileName == null || sizeRaw is! num || sha256 == null) {
      return null;
    }

    return TransferAnnouncementItem(
      fileName: fileName,
      sizeBytes: sizeRaw.toInt(),
      sha256: sha256,
    );
  }
}

class TransferRequestEvent {
  TransferRequestEvent({
    required this.requestId,
    required this.senderIp,
    required this.senderName,
    required this.senderMacAddress,
    required this.sharedCacheId,
    required this.sharedLabel,
    required this.items,
    required this.observedAt,
  });

  final String requestId;
  final String senderIp;
  final String senderName;
  final String senderMacAddress;
  final String sharedCacheId;
  final String sharedLabel;
  final List<TransferAnnouncementItem> items;
  final DateTime observedAt;
}

class TransferDecisionEvent {
  TransferDecisionEvent({
    required this.requestId,
    required this.approved,
    required this.receiverName,
    required this.receiverIp,
    required this.transferPort,
    required this.observedAt,
  });

  final String requestId;
  final bool approved;
  final String receiverName;
  final String receiverIp;
  final int? transferPort;
  final DateTime observedAt;
}

class ShareQueryEvent {
  ShareQueryEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final DateTime observedAt;
}

class SharedCatalogFileItem {
  SharedCatalogFileItem({
    required this.relativePath,
    required this.sizeBytes,
    this.thumbnailId,
  });

  final String relativePath;
  final int sizeBytes;
  final String? thumbnailId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'relativePath': relativePath,
      'sizeBytes': sizeBytes,
      'thumbnailId': thumbnailId,
    };
  }

  static SharedCatalogFileItem? fromJson(Map<String, dynamic> json) {
    final relativePath = json['relativePath'] as String?;
    final sizeRaw = json['sizeBytes'];
    if (relativePath == null || sizeRaw is! num) {
      return null;
    }
    return SharedCatalogFileItem(
      relativePath: relativePath,
      sizeBytes: sizeRaw.toInt(),
      thumbnailId: json['thumbnailId'] as String?,
    );
  }
}

class SharedCatalogEntryItem {
  SharedCatalogEntryItem({
    required this.cacheId,
    required this.displayName,
    required this.itemCount,
    required this.totalBytes,
    required this.files,
  });

  final String cacheId;
  final String displayName;
  final int itemCount;
  final int totalBytes;
  final List<SharedCatalogFileItem> files;

  Map<String, Object> toJson() {
    return <String, Object>{
      'cacheId': cacheId,
      'displayName': displayName,
      'itemCount': itemCount,
      'totalBytes': totalBytes,
      'files': files.map((file) => file.toJson()).toList(growable: false),
    };
  }

  static SharedCatalogEntryItem? fromJson(Map<String, dynamic> json) {
    final cacheId = json['cacheId'] as String?;
    final displayName = json['displayName'] as String?;
    final itemCountRaw = json['itemCount'];
    final totalBytesRaw = json['totalBytes'];
    final filesRaw = json['files'];
    if (cacheId == null ||
        displayName == null ||
        itemCountRaw is! num ||
        totalBytesRaw is! num ||
        filesRaw is! List<dynamic>) {
      return null;
    }

    final files = <SharedCatalogFileItem>[];
    for (final file in filesRaw) {
      if (file is! Map<String, dynamic>) {
        continue;
      }
      final parsed = SharedCatalogFileItem.fromJson(file);
      if (parsed != null) {
        files.add(parsed);
      }
    }
    return SharedCatalogEntryItem(
      cacheId: cacheId,
      displayName: displayName,
      itemCount: itemCountRaw.toInt(),
      totalBytes: totalBytesRaw.toInt(),
      files: files,
    );
  }
}

class ShareCatalogEvent {
  ShareCatalogEvent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
    required this.removedCacheIds,
    required this.observedAt,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final String ownerMacAddress;
  final List<SharedCatalogEntryItem> entries;
  final List<String> removedCacheIds;
  final DateTime observedAt;
}

class DownloadRequestEvent {
  DownloadRequestEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.cacheId,
    required this.selectedRelativePaths,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final String requesterMacAddress;
  final String cacheId;
  final List<String> selectedRelativePaths;
  final DateTime observedAt;
}

class ThumbnailSyncItem {
  const ThumbnailSyncItem({
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
  });

  final String cacheId;
  final String relativePath;
  final String thumbnailId;

  Map<String, Object> toJson() {
    return <String, Object>{
      'cacheId': cacheId,
      'relativePath': relativePath,
      'thumbnailId': thumbnailId,
    };
  }

  static ThumbnailSyncItem? fromJson(Map<String, dynamic> json) {
    final cacheId = json['cacheId'] as String?;
    final relativePath = json['relativePath'] as String?;
    final thumbnailId = json['thumbnailId'] as String?;
    if (cacheId == null || relativePath == null || thumbnailId == null) {
      return null;
    }
    return ThumbnailSyncItem(
      cacheId: cacheId,
      relativePath: relativePath,
      thumbnailId: thumbnailId,
    );
  }
}

class ThumbnailSyncRequestEvent {
  const ThumbnailSyncRequestEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.items,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final List<ThumbnailSyncItem> items;
  final DateTime observedAt;
}

class ThumbnailPacketEvent {
  const ThumbnailPacketEvent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
    required this.bytes,
    required this.observedAt,
  });

  final String requestId;
  final String ownerIp;
  final String ownerMacAddress;
  final String cacheId;
  final String relativePath;
  final String thumbnailId;
  final Uint8List bytes;
  final DateTime observedAt;
}

class LanDiscoveryService {
  static const int discoveryPort = 40404;
  static const String _discoverPrefix = 'LANDA_DISCOVER_V1';
  static const String _responsePrefix = 'LANDA_HERE_V1';
  static const String _transferRequestPrefix = 'LANDA_TRANSFER_REQUEST_V1';
  static const String _transferDecisionPrefix = 'LANDA_TRANSFER_DECISION_V1';
  static const String _shareQueryPrefix = 'LANDA_SHARE_QUERY_V1';
  static const String _shareCatalogPrefix = 'LANDA_SHARE_CATALOG_V1';
  static const String _downloadRequestPrefix = 'LANDA_DOWNLOAD_REQUEST_V1';
  static const String _thumbnailSyncRequestPrefix =
      'LANDA_THUMBNAIL_SYNC_REQUEST_V1';
  static const String _thumbnailPacketPrefix = 'LANDA_THUMBNAIL_PACKET_V1';
  static const MethodChannel _androidNetworkChannel = MethodChannel(
    'landa/network',
  );

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Set<String> _localIps = <String>{};
  bool _started = false;
  String? _preferredSourceIp;
  final String _instanceId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
  final String _operatingSystem = Platform.operatingSystem;
  late final String _deviceType = _resolveLocalDeviceType();
  static const List<String> _virtualInterfaceHints = <String>[
    'loopback',
    'docker',
    'vmware',
    'virtual',
    'vethernet',
    'hyper-v',
    'vbox',
    'wsl',
    'tailscale',
    'zerotier',
    'hamachi',
    'tun',
    'tap',
    'bridge',
  ];

  Future<void> start({
    required String deviceName,
    required void Function(AppPresenceEvent event) onAppDetected,
    void Function(TransferRequestEvent event)? onTransferRequest,
    void Function(TransferDecisionEvent event)? onTransferDecision,
    void Function(ShareQueryEvent event)? onShareQuery,
    void Function(ShareCatalogEvent event)? onShareCatalog,
    void Function(DownloadRequestEvent event)? onDownloadRequest,
    void Function(ThumbnailSyncRequestEvent event)? onThumbnailSyncRequest,
    void Function(ThumbnailPacketEvent event)? onThumbnailPacket,
    String? preferredSourceIp,
  }) async {
    if (_started) {
      _log('start() ignored: service already running');
      return;
    }
    _started = true;

    _preferredSourceIp = preferredSourceIp;
    _localIps = await _loadLocalIps(preferredSourceIp: preferredSourceIp);
    _log('Starting UDP discovery on $discoveryPort. localIps=$_localIps');
    await _acquireAndroidMulticastLock();

    // anyIPv4 is more reliable for receiving broadcast discovery packets
    // on Android devices; subnet filtering is applied in code.
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
      reusePort: false,
    );
    _socket?.broadcastEnabled = true;

    _socket?.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }

      Datagram? datagram = _socket?.receive();
      while (datagram != null) {
        final senderIp = datagram.address.address;
        if (_localIps.contains(senderIp)) {
          datagram = _socket?.receive();
          continue;
        }
        if (_preferredSourceIp != null &&
            !_isSame24Subnet(senderIp, _preferredSourceIp!)) {
          _log('Ignoring packet from foreign subnet: $senderIp');
          datagram = _socket?.receive();
          continue;
        }

        final message = utf8.decode(datagram.data, allowMalformed: true);
        final discoveryPacket = _parseDiscoveryPacket(message);
        if (discoveryPacket != null) {
          if (discoveryPacket.instanceId == _instanceId) {
            datagram = _socket?.receive();
            continue;
          }

          if (discoveryPacket.prefix == _discoverPrefix) {
            _log('Discover request from $senderIp');
            final responsePayload = _encodeDiscoveryPayload(deviceName);
            final response = '$_responsePrefix|$_instanceId|$responsePayload';
            _socket?.send(
              utf8.encode(response),
              datagram.address,
              discoveryPort,
            );
            _log('Discover response sent to $senderIp');
          } else if (discoveryPacket.prefix == _responsePrefix) {
            _log(
              'Discover response received from '
              '$senderIp (${discoveryPacket.deviceName})',
            );
            onAppDetected(
              AppPresenceEvent(
                ip: senderIp,
                deviceName: discoveryPacket.deviceName,
                operatingSystem: discoveryPacket.operatingSystem,
                deviceType: discoveryPacket.deviceType,
                observedAt: DateTime.now(),
              ),
            );
          }
          datagram = _socket?.receive();
          continue;
        }

        final transferRequest = _parseTransferRequestPacket(message);
        if (transferRequest != null) {
          if (transferRequest.instanceId == _instanceId) {
            datagram = _socket?.receive();
            continue;
          }
          _log(
            'Transfer request received from $senderIp '
            '(requestId=${transferRequest.requestId})',
          );
          onTransferRequest?.call(
            TransferRequestEvent(
              requestId: transferRequest.requestId,
              senderIp: senderIp,
              senderName: transferRequest.senderName,
              senderMacAddress: transferRequest.senderMacAddress,
              sharedCacheId: transferRequest.sharedCacheId,
              sharedLabel: transferRequest.sharedLabel,
              items: transferRequest.items,
              observedAt: DateTime.now(),
            ),
          );
          datagram = _socket?.receive();
          continue;
        }

        final transferDecision = _parseTransferDecisionPacket(message);
        if (transferDecision != null) {
          if (transferDecision.instanceId == _instanceId) {
            datagram = _socket?.receive();
            continue;
          }
          _log(
            'Transfer decision received from $senderIp '
            '(requestId=${transferDecision.requestId}, approved=${transferDecision.approved})',
          );
          onTransferDecision?.call(
            TransferDecisionEvent(
              requestId: transferDecision.requestId,
              approved: transferDecision.approved,
              receiverName: transferDecision.receiverName,
              receiverIp: senderIp,
              transferPort: transferDecision.transferPort,
              observedAt: DateTime.now(),
            ),
          );
          datagram = _socket?.receive();
          continue;
        }

        final shareQuery = _parseShareQueryPacket(message);
        if (shareQuery != null) {
          if (shareQuery.instanceId == _instanceId) {
            datagram = _socket?.receive();
            continue;
          }
          onShareQuery?.call(
            ShareQueryEvent(
              requestId: shareQuery.requestId,
              requesterIp: senderIp,
              requesterName: shareQuery.requesterName,
              observedAt: DateTime.now(),
            ),
          );
          datagram = _socket?.receive();
          continue;
        }

        final shareCatalog = _parseShareCatalogPacket(message);
        if (shareCatalog != null) {
          if (shareCatalog.instanceId == _instanceId) {
            datagram = _socket?.receive();
            continue;
          }
          onShareCatalog?.call(
            ShareCatalogEvent(
              requestId: shareCatalog.requestId,
              ownerIp: senderIp,
              ownerName: shareCatalog.ownerName,
              ownerMacAddress: shareCatalog.ownerMacAddress,
              entries: shareCatalog.entries,
              removedCacheIds: shareCatalog.removedCacheIds,
              observedAt: DateTime.now(),
            ),
          );
          datagram = _socket?.receive();
          continue;
        }

        final downloadRequest = _parseDownloadRequestPacket(message);
        if (downloadRequest != null) {
          if (downloadRequest.instanceId == _instanceId) {
            datagram = _socket?.receive();
            continue;
          }
          onDownloadRequest?.call(
            DownloadRequestEvent(
              requestId: downloadRequest.requestId,
              requesterIp: senderIp,
              requesterName: downloadRequest.requesterName,
              requesterMacAddress: downloadRequest.requesterMacAddress,
              cacheId: downloadRequest.cacheId,
              selectedRelativePaths: downloadRequest.selectedRelativePaths,
              observedAt: DateTime.now(),
            ),
          );
          datagram = _socket?.receive();
          continue;
        }

        final thumbnailSync = _parseThumbnailSyncRequestPacket(message);
        if (thumbnailSync != null) {
          if (thumbnailSync.instanceId == _instanceId) {
            datagram = _socket?.receive();
            continue;
          }
          onThumbnailSyncRequest?.call(
            ThumbnailSyncRequestEvent(
              requestId: thumbnailSync.requestId,
              requesterIp: senderIp,
              requesterName: thumbnailSync.requesterName,
              items: thumbnailSync.items,
              observedAt: DateTime.now(),
            ),
          );
          datagram = _socket?.receive();
          continue;
        }

        final thumbnailPacket = _parseThumbnailPacket(message);
        if (thumbnailPacket != null) {
          if (thumbnailPacket.instanceId == _instanceId) {
            datagram = _socket?.receive();
            continue;
          }
          onThumbnailPacket?.call(
            ThumbnailPacketEvent(
              requestId: thumbnailPacket.requestId,
              ownerIp: senderIp,
              ownerMacAddress: thumbnailPacket.ownerMacAddress,
              cacheId: thumbnailPacket.cacheId,
              relativePath: thumbnailPacket.relativePath,
              thumbnailId: thumbnailPacket.thumbnailId,
              bytes: thumbnailPacket.bytes,
              observedAt: DateTime.now(),
            ),
          );
          datagram = _socket?.receive();
          continue;
        }
        datagram = _socket?.receive();
      }
    });

    await _sendDiscoveryPing(deviceName);
    _beaconTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _sendDiscoveryPing(deviceName),
    );
  }

  Future<void> stop() async {
    _log('Stopping UDP discovery');
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _socket?.close();
    _socket = null;
    _started = false;
    await _releaseAndroidMulticastLock();
  }

  Future<void> sendTransferRequest({
    required String targetIp,
    required String requestId,
    required String senderName,
    required String senderMacAddress,
    required String sharedCacheId,
    required String sharedLabel,
    required List<TransferAnnouncementItem> items,
  }) async {
    final payload = <String, Object?>{
      'instanceId': _instanceId,
      'requestId': requestId,
      'senderName': senderName,
      'senderMacAddress': senderMacAddress,
      'sharedCacheId': sharedCacheId,
      'sharedLabel': sharedLabel,
      'items': items.map((item) => item.toJson()).toList(),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await _sendEncodedPacket(
      prefix: _transferRequestPrefix,
      payload: payload,
      targetIp: targetIp,
    );
  }

  Future<void> sendTransferDecision({
    required String targetIp,
    required String requestId,
    required bool approved,
    required String receiverName,
    int? transferPort,
  }) async {
    final payload = <String, Object?>{
      'instanceId': _instanceId,
      'requestId': requestId,
      'approved': approved,
      'receiverName': receiverName,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    if (transferPort != null) {
      payload['transferPort'] = transferPort;
    }
    await _sendEncodedPacket(
      prefix: _transferDecisionPrefix,
      payload: payload,
      targetIp: targetIp,
    );
  }

  Future<void> sendShareQuery({
    required String targetIp,
    required String requestId,
    required String requesterName,
  }) async {
    final payload = <String, Object?>{
      'instanceId': _instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await _sendEncodedPacket(
      prefix: _shareQueryPrefix,
      payload: payload,
      targetIp: targetIp,
    );
  }

  Future<void> sendShareCatalog({
    required String targetIp,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    List<String> removedCacheIds = const <String>[],
  }) async {
    final payload = <String, Object?>{
      'instanceId': _instanceId,
      'requestId': requestId,
      'ownerName': ownerName,
      'ownerMacAddress': ownerMacAddress,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'removedCacheIds': removedCacheIds,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await _sendEncodedPacket(
      prefix: _shareCatalogPrefix,
      payload: payload,
      targetIp: targetIp,
    );
  }

  Future<void> sendDownloadRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required String cacheId,
    List<String> selectedRelativePaths = const <String>[],
  }) async {
    final payload = <String, Object?>{
      'instanceId': _instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'requesterMacAddress': requesterMacAddress,
      'cacheId': cacheId,
      'selectedRelativePaths': selectedRelativePaths,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await _sendEncodedPacket(
      prefix: _downloadRequestPrefix,
      payload: payload,
      targetIp: targetIp,
    );
  }

  Future<void> sendThumbnailSyncRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required List<ThumbnailSyncItem> items,
  }) async {
    if (items.isEmpty) {
      return;
    }
    final payload = <String, Object?>{
      'instanceId': _instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await _sendEncodedPacket(
      prefix: _thumbnailSyncRequestPrefix,
      payload: payload,
      targetIp: targetIp,
    );
  }

  Future<void> sendThumbnailPacket({
    required String targetIp,
    required String requestId,
    required String ownerMacAddress,
    required String cacheId,
    required String relativePath,
    required String thumbnailId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      return;
    }
    final payload = <String, Object?>{
      'instanceId': _instanceId,
      'requestId': requestId,
      'ownerMacAddress': ownerMacAddress,
      'cacheId': cacheId,
      'relativePath': relativePath,
      'thumbnailId': thumbnailId,
      'bytesBase64': base64Encode(bytes),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await _sendEncodedPacket(
      prefix: _thumbnailPacketPrefix,
      payload: payload,
      targetIp: targetIp,
    );
  }

  Future<void> _sendEncodedPacket({
    required String prefix,
    required Map<String, Object?> payload,
    required String targetIp,
  }) async {
    final encodedPayload = base64UrlEncode(utf8.encode(jsonEncode(payload)));
    final message = '$prefix|$encodedPayload';
    _socket?.send(
      utf8.encode(message),
      InternetAddress(targetIp),
      discoveryPort,
    );
  }

  Future<void> _sendDiscoveryPing(String deviceName) async {
    final payload = _encodeDiscoveryPayload(deviceName);
    final request = '$_discoverPrefix|$_instanceId|$payload';
    final bytes = utf8.encode(request);

    _log('Broadcasting discover packet');
    _socket?.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);
    for (final localIp in _localIps) {
      final broadcast = _toBroadcastAddress(localIp);
      if (broadcast != null) {
        _socket?.send(bytes, broadcast, discoveryPort);
        _log('Discover packet sent to ${broadcast.address}');
      }
    }
  }

  _DiscoveryPacket? _parseDiscoveryPacket(String message) {
    final parts = message.split('|');
    if (parts.isEmpty) {
      return null;
    }

    final prefix = parts[0].trim();
    if (prefix != _discoverPrefix && prefix != _responsePrefix) {
      return null;
    }

    // Backward compatibility with old payload format: PREFIX|deviceName
    if (parts.length == 2) {
      final legacyName = parts[1].trim();
      return _DiscoveryPacket(
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
        return _DiscoveryPacket(
          prefix: prefix,
          instanceId: instanceId,
          deviceName: decodedPayload.deviceName,
          operatingSystem: decodedPayload.operatingSystem,
          deviceType: decodedPayload.deviceType,
        );
      }

      return _DiscoveryPacket(
        prefix: prefix,
        instanceId: instanceId,
        deviceName: rawPayload.isEmpty ? 'Unknown device' : rawPayload,
      );
    }

    return null;
  }

  String _encodeDiscoveryPayload(String deviceName) {
    final payload = <String, Object>{
      'name': deviceName,
      'os': _operatingSystem,
      'type': _deviceType,
    };
    return base64UrlEncode(utf8.encode(jsonEncode(payload)));
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
      return _DiscoveryIdentity(
        deviceName: (rawName == null || rawName.trim().isEmpty)
            ? 'Unknown device'
            : rawName.trim(),
        operatingSystem: _normalizeDiscoveryText(rawOs),
        deviceType: _normalizeDiscoveryText(rawType),
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

  String _resolveLocalDeviceType() {
    if (Platform.isAndroid || Platform.isIOS) {
      return 'phone';
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return 'pc';
    }
    return 'unknown';
  }

  _TransferRequestPacket? _parseTransferRequestPacket(String message) {
    final decoded = _decodeTransferEnvelope(
      message: message,
      expectedPrefix: _transferRequestPrefix,
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

    return _TransferRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      senderName: senderName,
      senderMacAddress: senderMacAddress,
      sharedCacheId: sharedCacheId,
      sharedLabel: sharedLabel,
      items: items,
    );
  }

  _TransferDecisionPacket? _parseTransferDecisionPacket(String message) {
    final decoded = _decodeTransferEnvelope(
      message: message,
      expectedPrefix: _transferDecisionPrefix,
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
    if (requestId == null ||
        receiverName == null ||
        approved == null ||
        instanceId == null) {
      return null;
    }

    return _TransferDecisionPacket(
      instanceId: instanceId,
      requestId: requestId,
      receiverName: receiverName,
      approved: approved,
      transferPort: transferPort,
    );
  }

  _ShareQueryPacket? _parseShareQueryPacket(String message) {
    final decoded = _decodeTransferEnvelope(
      message: message,
      expectedPrefix: _shareQueryPrefix,
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

    return _ShareQueryPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
    );
  }

  _ShareCatalogPacket? _parseShareCatalogPacket(String message) {
    final decoded = _decodeTransferEnvelope(
      message: message,
      expectedPrefix: _shareCatalogPrefix,
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

    return _ShareCatalogPacket(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      removedCacheIds: removedCacheIds,
    );
  }

  _DownloadRequestPacket? _parseDownloadRequestPacket(String message) {
    final decoded = _decodeTransferEnvelope(
      message: message,
      expectedPrefix: _downloadRequestPrefix,
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

    return _DownloadRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      cacheId: cacheId,
      selectedRelativePaths: selectedRelativePaths,
    );
  }

  _ThumbnailSyncRequestPacket? _parseThumbnailSyncRequestPacket(
    String message,
  ) {
    final decoded = _decodeTransferEnvelope(
      message: message,
      expectedPrefix: _thumbnailSyncRequestPrefix,
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

    return _ThumbnailSyncRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      items: items,
    );
  }

  _ThumbnailPacket? _parseThumbnailPacket(String message) {
    final decoded = _decodeTransferEnvelope(
      message: message,
      expectedPrefix: _thumbnailPacketPrefix,
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
      return _ThumbnailPacket(
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

  Map<String, dynamic>? _decodeTransferEnvelope({
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

  InternetAddress? _toBroadcastAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return null;
    }
    return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
  }

  Future<Set<String>> _loadLocalIps({String? preferredSourceIp}) async {
    if (preferredSourceIp != null && _isValidIpv4(preferredSourceIp)) {
      _log('Using preferred source IP for UDP discovery: $preferredSourceIp');
      return <String>{preferredSourceIp};
    }

    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final ips = <String>{};
    final fallbackIps = <String>{};
    for (final interface in interfaces) {
      final lowerName = interface.name.toLowerCase();
      final isVirtual = _virtualInterfaceHints.any(lowerName.contains);
      for (final address in interface.addresses) {
        if (isVirtual) {
          fallbackIps.add(address.address);
          continue;
        }
        ips.add(address.address);
      }
    }
    return ips.isNotEmpty ? ips : fallbackIps;
  }

  bool _isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        return false;
      }
    }
    return true;
  }

  bool _isSame24Subnet(String ip, String baseIp) {
    if (!_isValidIpv4(ip) || !_isValidIpv4(baseIp)) {
      return false;
    }
    final a = ip.split('.');
    final b = baseIp.split('.');
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
  }

  void _log(String message) {
    developer.log(message, name: 'LanDiscoveryService');
  }

  Future<void> _acquireAndroidMulticastLock() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidNetworkChannel.invokeMethod<void>('acquireMulticastLock');
      _log('Android multicast lock acquired');
    } catch (error) {
      _log('Failed to acquire Android multicast lock: $error');
    }
  }

  Future<void> _releaseAndroidMulticastLock() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidNetworkChannel.invokeMethod<void>('releaseMulticastLock');
      _log('Android multicast lock released');
    } catch (error) {
      _log('Failed to release Android multicast lock: $error');
    }
  }
}

class _DiscoveryPacket {
  const _DiscoveryPacket({
    required this.prefix,
    required this.instanceId,
    required this.deviceName,
    this.operatingSystem,
    this.deviceType,
  });

  final String prefix;
  final String instanceId;
  final String deviceName;
  final String? operatingSystem;
  final String? deviceType;
}

class _DiscoveryIdentity {
  const _DiscoveryIdentity({
    required this.deviceName,
    this.operatingSystem,
    this.deviceType,
  });

  final String deviceName;
  final String? operatingSystem;
  final String? deviceType;
}

class _TransferRequestPacket {
  const _TransferRequestPacket({
    required this.instanceId,
    required this.requestId,
    required this.senderName,
    required this.senderMacAddress,
    required this.sharedCacheId,
    required this.sharedLabel,
    required this.items,
  });

  final String instanceId;
  final String requestId;
  final String senderName;
  final String senderMacAddress;
  final String sharedCacheId;
  final String sharedLabel;
  final List<TransferAnnouncementItem> items;
}

class _TransferDecisionPacket {
  const _TransferDecisionPacket({
    required this.instanceId,
    required this.requestId,
    required this.receiverName,
    required this.approved,
    required this.transferPort,
  });

  final String instanceId;
  final String requestId;
  final String receiverName;
  final bool approved;
  final int? transferPort;
}

class _ShareQueryPacket {
  const _ShareQueryPacket({
    required this.instanceId,
    required this.requestId,
    required this.requesterName,
  });

  final String instanceId;
  final String requestId;
  final String requesterName;
}

class _ShareCatalogPacket {
  const _ShareCatalogPacket({
    required this.instanceId,
    required this.requestId,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
    required this.removedCacheIds,
  });

  final String instanceId;
  final String requestId;
  final String ownerName;
  final String ownerMacAddress;
  final List<SharedCatalogEntryItem> entries;
  final List<String> removedCacheIds;
}

class _DownloadRequestPacket {
  const _DownloadRequestPacket({
    required this.instanceId,
    required this.requestId,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.cacheId,
    required this.selectedRelativePaths,
  });

  final String instanceId;
  final String requestId;
  final String requesterName;
  final String requesterMacAddress;
  final String cacheId;
  final List<String> selectedRelativePaths;
}

class _ThumbnailSyncRequestPacket {
  const _ThumbnailSyncRequestPacket({
    required this.instanceId,
    required this.requestId,
    required this.requesterName,
    required this.items,
  });

  final String instanceId;
  final String requestId;
  final String requesterName;
  final List<ThumbnailSyncItem> items;
}

class _ThumbnailPacket {
  const _ThumbnailPacket({
    required this.instanceId,
    required this.requestId,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
    required this.bytes,
  });

  final String instanceId;
  final String requestId;
  final String ownerMacAddress;
  final String cacheId;
  final String relativePath;
  final String thumbnailId;
  final Uint8List bytes;
}

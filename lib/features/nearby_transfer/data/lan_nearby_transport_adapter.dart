import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../transfer/data/file_hash_service.dart';
import '../../transfer/data/file_transfer_service.dart';
import '../../transfer/domain/transfer_request.dart';
import 'nearby_transfer_storage_service.dart';
import 'nearby_transfer_transport_adapter.dart';

class LanNearbyTransportAdapter implements NearbyTransferTransportAdapter {
  LanNearbyTransportAdapter({
    required FileHashService fileHashService,
    required FileTransferService fileTransferService,
    required NearbyTransferStorageService storageService,
    this.preferredPort = 45321,
  }) : _fileHashService = fileHashService,
       _fileTransferService = fileTransferService,
       _storageService = storageService;

  final FileHashService _fileHashService;
  final FileTransferService _fileTransferService;
  final NearbyTransferStorageService _storageService;
  final int preferredPort;

  final StreamController<NearbyTransferTransportEvent> _events =
      StreamController<NearbyTransferTransportEvent>.broadcast();
  final Map<String, _PendingOutgoingOffer> _pendingOutgoingOffers =
      <String, _PendingOutgoingOffer>{};
  final Map<String, _PendingIncomingOffer> _pendingIncomingOffers =
      <String, _PendingIncomingOffer>{};
  final Map<String, TransferReceiveSession> _receiveSessions =
      <String, TransferReceiveSession>{};
  Future<void> _pendingControlWrite = Future<void>.value();

  ServerSocket? _server;
  Socket? _activeSocket;
  StreamSubscription<String>? _activeSocketLines;
  String? _sessionId;
  String? _expectedSessionId;
  String? _localDeviceId;
  String? _localDeviceName;
  NearbyTransferPeerDevice? _peer;
  bool _disposed = false;

  @override
  bool get isSupported => true;

  @override
  int? get visibleCandidatePort => preferredPort;

  @override
  Stream<NearbyTransferTransportEvent> get events => _events.stream;

  @override
  Future<NearbyTransferHostingInfo> startHostingSession({
    required String sessionId,
    required String localDeviceId,
    required String localDeviceName,
  }) async {
    _sessionId = sessionId;
    _localDeviceId = localDeviceId;
    _localDeviceName = localDeviceName;
    if (_server != null) {
      return NearbyTransferHostingInfo(
        port: _server!.port,
        supportsVisibleCandidatePairing: _server!.port == preferredPort,
      );
    }

    ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, preferredPort);
    } on SocketException {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    }
    _server = server;
    server.listen(_handleIncomingSocket);
    return NearbyTransferHostingInfo(
      port: server.port,
      supportsVisibleCandidatePairing: server.port == preferredPort,
    );
  }

  @override
  Future<void> connectToSession({
    required String host,
    required int port,
    required String localDeviceId,
    required String localDeviceName,
    String? expectedSessionId,
  }) async {
    _localDeviceId = localDeviceId;
    _localDeviceName = localDeviceName;
    _expectedSessionId = expectedSessionId;
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
    );
    await _attachSocket(socket);
    await _sendControlMessage(<String, Object?>{
      'type': 'connect',
      'sessionId': expectedSessionId,
      'deviceId': localDeviceId,
      'deviceName': localDeviceName,
    });
  }

  @override
  Future<void> sendHandshakeOffer(List<String> verificationCode) async {
    await _sendControlMessage(<String, Object?>{
      'type': 'handshakeOffer',
      'verificationCode': verificationCode,
    });
  }

  @override
  Future<void> sendHandshakeAccepted() async {
    await _sendControlMessage(<String, Object?>{'type': 'handshakeAccepted'});
  }

  @override
  Future<void> sendSelection(NearbyTransferSelection selection) async {
    final sessionId = _sessionId;
    if (_activeSocket == null || _peer == null || sessionId == null) {
      throw StateError('Nearby transfer is not connected.');
    }

    final requestId = _fileHashService.buildStableId(
      '$sessionId-${DateTime.now().microsecondsSinceEpoch}',
    );
    final entries = <_PendingOutgoingOfferEntry>[];
    for (final entry in selection.entries) {
      final sha256 = await _fileHashService.computeSha256ForPath(
        entry.sourcePath,
      );
      final fileId = _fileHashService.buildStableId(
        '${entry.relativePath}|${entry.sizeBytes}|$sha256',
      );
      final previewKind = _resolvePreviewKind(
        entry.relativePath,
        entry.sizeBytes,
      );
      entries.add(
        _PendingOutgoingOfferEntry(
          fileId: fileId,
          sourceFile: TransferSourceFile(
            sourcePath: entry.sourcePath,
            fileName: entry.relativePath,
            sizeBytes: entry.sizeBytes,
            sha256: sha256,
          ),
          manifestItem: TransferFileManifestItem(
            fileName: entry.relativePath,
            sizeBytes: entry.sizeBytes,
            sha256: sha256,
          ),
          previewKind: previewKind,
        ),
      );
    }

    _pendingOutgoingOffers[requestId] = _PendingOutgoingOffer(
      requestId: requestId,
      label: selection.label,
      entries: entries,
      roots: _buildOfferRoots(entries),
    );
    final offer = _pendingOutgoingOffers[requestId]!;
    await _sendControlMessage(<String, Object?>{
      'type': 'fileOffer',
      'sessionId': sessionId,
      'requestId': requestId,
      'label': selection.label,
      'files': entries.map((entry) => entry.toJson()).toList(growable: false),
      'roots': offer.roots
          .map((node) => _offerNodeToJson(node))
          .toList(growable: false),
    });
  }

  @override
  Future<void> requestIncomingSelectionPreview({
    required String requestId,
    required String fileId,
  }) async {
    await _sendControlMessage(<String, Object?>{
      'type': 'filePreviewRequest',
      'requestId': requestId,
      'fileId': fileId,
    });
  }

  @override
  Future<void> requestIncomingSelectionDownload({
    required String requestId,
    required List<String> fileIds,
  }) async {
    final offer = _pendingIncomingOffers[requestId];
    if (offer == null) {
      throw StateError('Incoming nearby offer is not available anymore.');
    }

    final normalizedFileIds = fileIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedFileIds.isEmpty) {
      throw StateError('Select at least one file to download.');
    }

    final selectedEntries = offer.entriesById.values
        .where((entry) => normalizedFileIds.contains(entry.remote.id))
        .toList(growable: false);
    if (selectedEntries.isEmpty) {
      throw StateError('Requested nearby files are not available.');
    }

    final destinationDirectory = await _storageService
        .resolveReceiveDirectory();
    final receiveSession = await _fileTransferService.startReceiver(
      requestId: requestId,
      expectedItems: selectedEntries
          .map((entry) => entry.manifest)
          .toList(growable: false),
      destinationDirectory: destinationDirectory,
      destinationPathAllocator:
          ({
            required Directory destinationDirectory,
            required String relativePath,
          }) {
            return _storageService.allocateDestinationPath(
              destinationDirectory: destinationDirectory,
              relativePath: relativePath,
            );
          },
      onProgress: (receivedBytes, totalBytes) {
        _events.add(
          NearbyTransferTransferProgressEvent(
            direction: NearbyTransferProgressDirection.receiving,
            completedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      },
    );
    _receiveSessions[requestId] = receiveSession;
    await _sendControlMessage(<String, Object?>{
      'type': 'fileReceiverReady',
      'requestId': requestId,
      'port': receiveSession.port,
      'fileIds': normalizedFileIds,
    });

    unawaited(
      receiveSession.result.then((result) {
        _receiveSessions.remove(requestId);
        if (result.success) {
          _pendingIncomingOffers.remove(requestId);
          _events.add(
            NearbyTransferTransferCompletedEvent(
              direction: NearbyTransferProgressDirection.receiving,
              message: result.message,
              savedPaths: result.savedPaths,
            ),
          );
        } else {
          _events.add(NearbyTransferErrorEvent(message: result.message));
        }
      }),
    );
  }

  @override
  Future<void> disconnect() async {
    final socket = _activeSocket;
    _activeSocket = null;
    _peer = null;
    _expectedSessionId = null;
    await _activeSocketLines?.cancel();
    _activeSocketLines = null;
    if (socket != null) {
      await socket.close();
      socket.destroy();
    }
    for (final session in _receiveSessions.values) {
      await session.close();
    }
    _receiveSessions.clear();
    _pendingIncomingOffers.clear();
    _pendingOutgoingOffers.clear();
    await _server?.close();
    _server = null;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(disconnect());
    _events.close();
  }

  void _handleIncomingSocket(Socket socket) {
    if (_activeSocket != null) {
      unawaited(_rejectSocket(socket, 'busy'));
      return;
    }
    unawaited(_attachSocket(socket));
  }

  Future<void> _attachSocket(Socket socket) async {
    _activeSocket = socket;
    _pendingControlWrite = Future<void>.value();
    _activeSocketLines?.cancel();
    _activeSocketLines = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => unawaited(_handleMessage(socket, line)),
          onDone: () => unawaited(_handleSocketClosed(socket)),
          onError: (Object error) {
            _events.add(
              NearbyTransferErrorEvent(
                message: 'Nearby transport socket error: $error',
              ),
            );
            unawaited(_handleSocketClosed(socket));
          },
          cancelOnError: true,
        );
  }

  Future<void> _handleMessage(Socket socket, String line) async {
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) {
        json = decoded;
      }
    } catch (_) {
      json = null;
    }
    if (json == null) {
      return;
    }

    final type = json['type'] as String?;
    if (type == null) {
      return;
    }

    if (type == 'connect') {
      await _handleConnectMessage(socket, json);
      return;
    }
    if (type == 'connectAccepted') {
      _handleConnectAccepted(json);
      return;
    }
    if (type == 'handshakeOffer') {
      final sequence = (json['verificationCode'] as List<dynamic>?)
          ?.whereType<String>()
          .toList(growable: false);
      if (sequence != null && sequence.isNotEmpty) {
        _events.add(
          NearbyTransferHandshakeOfferEvent(verificationCode: sequence),
        );
      }
      return;
    }
    if (type == 'handshakeAccepted') {
      _events.add(const NearbyTransferHandshakeAcceptedEvent());
      return;
    }
    if (type == 'fileOffer') {
      _handleFileOffer(json);
      return;
    }
    if (type == 'filePreviewRequest') {
      await _handlePreviewRequest(json);
      return;
    }
    if (type == 'filePreviewReady') {
      _handlePreviewReady(json);
      return;
    }
    if (type == 'fileReceiverReady') {
      await _handleFileReceiverReady(json);
      return;
    }
    if (type == 'reject') {
      final message = json['message'] as String? ?? 'Подключение отклонено.';
      _events.add(NearbyTransferErrorEvent(message: message));
      await _handleSocketClosed(socket);
      return;
    }
    if (type == 'error') {
      final message = json['message'] as String?;
      if (message != null && message.trim().isNotEmpty) {
        _events.add(NearbyTransferErrorEvent(message: message));
      }
    }
  }

  Future<void> _handleConnectMessage(
    Socket socket,
    Map<String, dynamic> json,
  ) async {
    final localSessionId = _sessionId;
    final deviceId = json['deviceId'] as String?;
    final deviceName = json['deviceName'] as String?;
    final expectedSessionId = json['sessionId'] as String?;
    if (localSessionId == null ||
        deviceId == null ||
        deviceName == null ||
        deviceId.trim().isEmpty ||
        deviceName.trim().isEmpty) {
      await _rejectSocket(socket, 'invalid session handshake');
      return;
    }
    if (expectedSessionId != null &&
        expectedSessionId.trim().isNotEmpty &&
        expectedSessionId.trim() != localSessionId) {
      await _rejectSocket(socket, 'session mismatch');
      return;
    }

    _peer = NearbyTransferPeerDevice(
      deviceId: deviceId.trim(),
      displayName: deviceName.trim(),
      host: socket.remoteAddress.address,
    );
    await _sendControlMessage(<String, Object?>{
      'type': 'connectAccepted',
      'sessionId': localSessionId,
      'deviceId': _localDeviceId ?? 'unknown-device',
      'deviceName': _localDeviceName ?? 'Landa',
    });
    _events.add(
      NearbyTransferConnectedEvent(peer: _peer!, sessionId: localSessionId),
    );
  }

  void _handleConnectAccepted(Map<String, dynamic> json) {
    final sessionId = json['sessionId'] as String?;
    final deviceId = json['deviceId'] as String?;
    final deviceName = json['deviceName'] as String?;
    final socket = _activeSocket;
    if (socket == null ||
        sessionId == null ||
        deviceId == null ||
        deviceName == null) {
      return;
    }

    final expectedSessionId = _expectedSessionId;
    if (expectedSessionId != null &&
        expectedSessionId.trim().isNotEmpty &&
        expectedSessionId != sessionId) {
      _events.add(
        const NearbyTransferErrorEvent(message: 'QR session does not match.'),
      );
      unawaited(_handleSocketClosed(socket));
      return;
    }

    _sessionId = sessionId;
    _peer = NearbyTransferPeerDevice(
      deviceId: deviceId,
      displayName: deviceName,
      host: socket.remoteAddress.address,
    );
    _events.add(
      NearbyTransferConnectedEvent(peer: _peer!, sessionId: sessionId),
    );
  }

  void _handleFileOffer(Map<String, dynamic> json) {
    final sessionId = json['sessionId'] as String?;
    final requestId = json['requestId'] as String?;
    final label = json['label'] as String?;
    final rawFiles = json['files'];
    final rawRoots = json['roots'];
    if (_activeSocket == null ||
        _sessionId == null ||
        sessionId != _sessionId ||
        requestId == null ||
        label == null ||
        rawFiles is! List<dynamic> ||
        rawRoots is! List<dynamic>) {
      return;
    }

    final offerEntries = rawFiles
        .whereType<Map<String, dynamic>>()
        .map(_IncomingOfferEntry.fromJson)
        .toList(growable: false);
    if (offerEntries.isEmpty) {
      return;
    }

    _pendingIncomingOffers[requestId] = _PendingIncomingOffer(
      requestId: requestId,
      label: label,
      roots: rawRoots
          .whereType<Map<String, dynamic>>()
          .map(_offerNodeFromJson)
          .toList(growable: false),
      entriesById: <String, _IncomingOfferEntry>{
        for (final entry in offerEntries) entry.remote.id: entry,
      },
    );
    final offer = _pendingIncomingOffers[requestId]!;
    _events.add(
      NearbyTransferIncomingSelectionOfferedEvent(
        requestId: requestId,
        label: label,
        roots: offer.roots,
      ),
    );
  }

  Future<void> _handlePreviewRequest(Map<String, dynamic> json) async {
    final requestId = json['requestId'] as String?;
    final fileId = json['fileId'] as String?;
    if (requestId == null || fileId == null) {
      return;
    }

    final offer = _pendingOutgoingOffers[requestId];
    final entry = offer?.entryById(fileId);
    if (entry == null) {
      return;
    }

    final payload = await _buildPreviewPayload(
      requestId: requestId,
      entry: entry,
    );
    if (payload == null) {
      return;
    }
    await _sendControlMessage(payload);
  }

  void _handlePreviewReady(Map<String, dynamic> json) {
    final requestId = json['requestId'] as String?;
    final fileId = json['fileId'] as String?;
    final previewKindName = json['previewKind'] as String?;
    if (requestId == null || fileId == null || previewKindName == null) {
      return;
    }
    final previewKind = NearbyTransferRemotePreviewKind.values.firstWhere(
      (value) => value.name == previewKindName,
      orElse: () => NearbyTransferRemotePreviewKind.none,
    );
    if (previewKind == NearbyTransferRemotePreviewKind.text) {
      final text = json['text'] as String?;
      if (text == null) {
        return;
      }
      _events.add(
        NearbyTransferRemotePreviewReadyEvent(
          preview: NearbyTransferRemoteFilePreview.text(
            requestId: requestId,
            fileId: fileId,
            textContent: text,
            isTruncated: json['isTruncated'] as bool? ?? false,
          ),
        ),
      );
      return;
    }
    if (previewKind == NearbyTransferRemotePreviewKind.image) {
      final encodedBytes = json['bytesBase64'] as String?;
      if (encodedBytes == null) {
        return;
      }
      _events.add(
        NearbyTransferRemotePreviewReadyEvent(
          preview: NearbyTransferRemoteFilePreview.image(
            requestId: requestId,
            fileId: fileId,
            imageBytes: base64Decode(encodedBytes),
          ),
        ),
      );
    }
  }

  Future<void> _handleFileReceiverReady(Map<String, dynamic> json) async {
    final requestId = json['requestId'] as String?;
    final port = (json['port'] as num?)?.toInt();
    final rawFileIds = json['fileIds'] as List<dynamic>?;
    final peer = _peer;
    if (requestId == null ||
        port == null ||
        rawFileIds == null ||
        peer == null) {
      return;
    }
    final selectedIds = rawFileIds.whereType<String>().toSet();
    if (selectedIds.isEmpty) {
      return;
    }
    final offer = _pendingOutgoingOffers.remove(requestId);
    if (offer == null) {
      return;
    }

    final selectedEntries = offer.entries
        .where((entry) => selectedIds.contains(entry.fileId))
        .toList(growable: false);
    if (selectedEntries.isEmpty) {
      return;
    }

    final totalBytes = selectedEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.sourceFile.sizeBytes,
    );
    await _fileTransferService.sendFiles(
      host: peer.host,
      port: port,
      requestId: requestId,
      files: selectedEntries
          .map((entry) => entry.sourceFile)
          .toList(growable: false),
      onProgress: (sentBytes, totalBytesValue) {
        _events.add(
          NearbyTransferTransferProgressEvent(
            direction: NearbyTransferProgressDirection.sending,
            completedBytes: sentBytes,
            totalBytes: totalBytesValue == 0 ? totalBytes : totalBytesValue,
          ),
        );
      },
    );
    _events.add(
      NearbyTransferTransferCompletedEvent(
        direction: NearbyTransferProgressDirection.sending,
        message: '${offer.label}: отправка завершена.',
      ),
    );
  }

  Future<void> _rejectSocket(Socket socket, String reason) async {
    try {
      socket.write(
        jsonEncode(<String, Object?>{'type': 'reject', 'message': reason}),
      );
      socket.write('\n');
      await socket.flush();
    } catch (_) {
      // Ignore best-effort reject messaging.
    } finally {
      await socket.close();
      socket.destroy();
    }
  }

  Future<void> _sendControlMessage(Map<String, Object?> payload) async {
    final socket = _activeSocket;
    if (socket == null) {
      throw StateError('Nearby transfer socket is not connected.');
    }
    final encodedPayload = '${jsonEncode(payload)}\n';
    final writeFuture = _pendingControlWrite.then((_) async {
      if (!identical(socket, _activeSocket)) {
        throw StateError('Nearby transfer socket is not connected.');
      }
      socket.write(encodedPayload);
      await socket.flush();
    });
    _pendingControlWrite = writeFuture.catchError((_) {});
    await writeFuture;
  }

  Future<void> _handleSocketClosed(Socket socket) async {
    if (!identical(socket, _activeSocket)) {
      return;
    }
    _peer = null;
    _expectedSessionId = null;
    _activeSocket = null;
    _pendingControlWrite = Future<void>.value();
    await _activeSocketLines?.cancel();
    _activeSocketLines = null;
    try {
      await socket.close();
    } catch (_) {}
    socket.destroy();
    _events.add(
      const NearbyTransferDisconnectedEvent(message: 'Соединение закрыто.'),
    );
  }

  NearbyTransferRemotePreviewKind _resolvePreviewKind(
    String relativePath,
    int sizeBytes,
  ) {
    final extension = p.extension(relativePath).toLowerCase();
    if (_previewableTextExtensions.contains(extension)) {
      return NearbyTransferRemotePreviewKind.text;
    }
    if (_previewableImageExtensions.contains(extension) &&
        sizeBytes <= _maxInlineImagePreviewBytes) {
      return NearbyTransferRemotePreviewKind.image;
    }
    return NearbyTransferRemotePreviewKind.none;
  }

  Future<Map<String, Object?>?> _buildPreviewPayload({
    required String requestId,
    required _PendingOutgoingOfferEntry entry,
  }) async {
    final file = File(entry.sourceFile.sourcePath);
    if (!await file.exists()) {
      return null;
    }

    switch (entry.previewKind) {
      case NearbyTransferRemotePreviewKind.none:
        return null;
      case NearbyTransferRemotePreviewKind.text:
        final bytes = await file.readAsBytes();
        final truncated = bytes.length > _maxInlineTextPreviewBytes;
        final previewBytes = truncated
            ? bytes.sublist(0, _maxInlineTextPreviewBytes)
            : bytes;
        return <String, Object?>{
          'type': 'filePreviewReady',
          'requestId': requestId,
          'fileId': entry.fileId,
          'previewKind': NearbyTransferRemotePreviewKind.text.name,
          'text': utf8.decode(previewBytes, allowMalformed: true),
          'isTruncated': truncated,
        };
      case NearbyTransferRemotePreviewKind.image:
        final bytes = await file.readAsBytes();
        if (bytes.length > _maxInlineImagePreviewBytes) {
          return null;
        }
        return <String, Object?>{
          'type': 'filePreviewReady',
          'requestId': requestId,
          'fileId': entry.fileId,
          'previewKind': NearbyTransferRemotePreviewKind.image.name,
          'bytesBase64': base64Encode(bytes),
        };
    }
  }
}

const Set<String> _previewableTextExtensions = <String>{
  '.txt',
  '.md',
  '.json',
  '.yaml',
  '.yml',
  '.csv',
  '.log',
};

const Set<String> _previewableImageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
};

const int _maxInlineTextPreviewBytes = 64 * 1024;
const int _maxInlineImagePreviewBytes = 2 * 1024 * 1024;

class _PendingOutgoingOffer {
  const _PendingOutgoingOffer({
    required this.requestId,
    required this.label,
    required this.entries,
    required this.roots,
  });

  final String requestId;
  final String label;
  final List<_PendingOutgoingOfferEntry> entries;
  final List<NearbyTransferRemoteOfferNode> roots;

  _PendingOutgoingOfferEntry? entryById(String fileId) {
    for (final entry in entries) {
      if (entry.fileId == fileId) {
        return entry;
      }
    }
    return null;
  }
}

class _PendingOutgoingOfferEntry {
  const _PendingOutgoingOfferEntry({
    required this.fileId,
    required this.sourceFile,
    required this.manifestItem,
    required this.previewKind,
  });

  final String fileId;
  final TransferSourceFile sourceFile;
  final TransferFileManifestItem manifestItem;
  final NearbyTransferRemotePreviewKind previewKind;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': fileId,
      'fileName': manifestItem.fileName,
      'sizeBytes': manifestItem.sizeBytes,
      'sha256': manifestItem.sha256,
      'previewKind': previewKind.name,
    };
  }
}

class _PendingIncomingOffer {
  const _PendingIncomingOffer({
    required this.requestId,
    required this.label,
    required this.roots,
    required this.entriesById,
  });

  final String requestId;
  final String label;
  final List<NearbyTransferRemoteOfferNode> roots;
  final Map<String, _IncomingOfferEntry> entriesById;
}

class _IncomingOfferEntry {
  const _IncomingOfferEntry({required this.remote, required this.manifest});

  final NearbyTransferRemoteFileDescriptor remote;
  final TransferFileManifestItem manifest;

  static _IncomingOfferEntry fromJson(Map<String, dynamic> json) {
    final previewKind = NearbyTransferRemotePreviewKind.values.firstWhere(
      (value) => value.name == (json['previewKind'] as String?),
      orElse: () => NearbyTransferRemotePreviewKind.none,
    );
    return _IncomingOfferEntry(
      remote: NearbyTransferRemoteFileDescriptor(
        id: json['id'] as String,
        name: p.basename(json['fileName'] as String),
        relativePath: json['fileName'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        previewKind: previewKind,
      ),
      manifest: TransferFileManifestItem(
        fileName: json['fileName'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        sha256: json['sha256'] as String,
      ),
    );
  }
}

List<NearbyTransferRemoteOfferNode> _buildOfferRoots(
  List<_PendingOutgoingOfferEntry> entries,
) {
  final roots = <_MutableOfferNode>[];
  final directoryByPath = <String, _MutableOfferNode>{};

  for (final entry in entries) {
    final relativePath = entry.manifestItem.fileName;
    final normalizedSegments = p
        .split(relativePath)
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (normalizedSegments.isEmpty) {
      continue;
    }

    var currentChildren = roots;
    var currentPath = '';
    for (var index = 0; index < normalizedSegments.length - 1; index += 1) {
      final segment = normalizedSegments[index];
      currentPath = currentPath.isEmpty
          ? segment
          : p.join(currentPath, segment);
      final existingDirectory = directoryByPath[currentPath];
      if (existingDirectory != null) {
        currentChildren = existingDirectory.children;
        continue;
      }
      final directory = _MutableOfferNode.directory(
        id: 'dir:$currentPath',
        name: segment,
        relativePath: currentPath,
      );
      currentChildren.add(directory);
      directoryByPath[currentPath] = directory;
      currentChildren = directory.children;
    }

    final fileName = normalizedSegments.last;
    currentChildren.add(
      _MutableOfferNode.file(
        id: entry.fileId,
        name: fileName,
        relativePath: relativePath,
        sizeBytes: entry.manifestItem.sizeBytes,
        previewKind: entry.previewKind,
      ),
    );
  }

  return roots.map((node) => node.toImmutable()).toList(growable: false);
}

Map<String, Object?> _offerNodeToJson(NearbyTransferRemoteOfferNode node) {
  return <String, Object?>{
    'id': node.id,
    'name': node.name,
    'relativePath': node.relativePath,
    'kind': node.kind.name,
    'sizeBytes': node.sizeBytes,
    'previewKind': node.previewKind.name,
    'children': node.children
        .map((child) => _offerNodeToJson(child))
        .toList(growable: false),
  };
}

NearbyTransferRemoteOfferNode _offerNodeFromJson(Map<String, dynamic> json) {
  final kind = NearbyTransferRemoteOfferNodeKind.values.firstWhere(
    (value) => value.name == (json['kind'] as String?),
    orElse: () => NearbyTransferRemoteOfferNodeKind.file,
  );
  final previewKind = NearbyTransferRemotePreviewKind.values.firstWhere(
    (value) => value.name == (json['previewKind'] as String?),
    orElse: () => NearbyTransferRemotePreviewKind.none,
  );
  final children = (json['children'] as List<dynamic>? ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map(_offerNodeFromJson)
      .toList(growable: false);
  return NearbyTransferRemoteOfferNode(
    id: json['id'] as String,
    name: json['name'] as String,
    relativePath: json['relativePath'] as String,
    kind: kind,
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    previewKind: previewKind,
    children: children,
  );
}

class _MutableOfferNode {
  _MutableOfferNode._({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.kind,
    required this.sizeBytes,
    required this.previewKind,
    List<_MutableOfferNode>? children,
  }) : children = children ?? <_MutableOfferNode>[];

  factory _MutableOfferNode.directory({
    required String id,
    required String name,
    required String relativePath,
  }) {
    return _MutableOfferNode._(
      id: id,
      name: name,
      relativePath: relativePath,
      kind: NearbyTransferRemoteOfferNodeKind.directory,
      sizeBytes: 0,
      previewKind: NearbyTransferRemotePreviewKind.none,
    );
  }

  factory _MutableOfferNode.file({
    required String id,
    required String name,
    required String relativePath,
    required int sizeBytes,
    required NearbyTransferRemotePreviewKind previewKind,
  }) {
    return _MutableOfferNode._(
      id: id,
      name: name,
      relativePath: relativePath,
      kind: NearbyTransferRemoteOfferNodeKind.file,
      sizeBytes: sizeBytes,
      previewKind: previewKind,
    );
  }

  final String id;
  final String name;
  final String relativePath;
  final NearbyTransferRemoteOfferNodeKind kind;
  final int sizeBytes;
  final NearbyTransferRemotePreviewKind previewKind;
  final List<_MutableOfferNode> children;

  NearbyTransferRemoteOfferNode toImmutable() {
    final immutableChildren = children
        .map((child) => child.toImmutable())
        .toList(growable: false);
    final resolvedSize = kind == NearbyTransferRemoteOfferNodeKind.file
        ? sizeBytes
        : immutableChildren.fold<int>(0, (sum, child) => sum + child.sizeBytes);
    return NearbyTransferRemoteOfferNode(
      id: id,
      name: name,
      relativePath: relativePath,
      kind: kind,
      sizeBytes: resolvedSize,
      previewKind: previewKind,
      children: immutableChildren,
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  final Map<String, Completer<int>> _pendingSenderPorts =
      <String, Completer<int>>{};
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
  Future<void> sendHandshakeOffer(List<String> emojiSequence) async {
    await _sendControlMessage(<String, Object?>{
      'type': 'handshakeOffer',
      'emojiSequence': emojiSequence,
    });
  }

  @override
  Future<void> sendHandshakeAccepted() async {
    await _sendControlMessage(<String, Object?>{'type': 'handshakeAccepted'});
  }

  @override
  Future<void> sendSelection(NearbyTransferSelection selection) async {
    final socket = _activeSocket;
    final peer = _peer;
    final sessionId = _sessionId;
    if (socket == null || peer == null || sessionId == null) {
      throw StateError('Nearby transfer is not connected.');
    }

    final requestId = _fileHashService.buildStableId(
      '$sessionId-${DateTime.now().microsecondsSinceEpoch}',
    );
    final sources = <TransferSourceFile>[];
    final manifest = <TransferFileManifestItem>[];
    for (final entry in selection.entries) {
      final sha256 = await _fileHashService.computeSha256ForPath(
        entry.sourcePath,
      );
      sources.add(
        TransferSourceFile(
          sourcePath: entry.sourcePath,
          fileName: entry.relativePath,
          sizeBytes: entry.sizeBytes,
          sha256: sha256,
        ),
      );
      manifest.add(
        TransferFileManifestItem(
          fileName: entry.relativePath,
          sizeBytes: entry.sizeBytes,
          sha256: sha256,
        ),
      );
    }

    final portCompleter = Completer<int>();
    _pendingSenderPorts[requestId] = portCompleter;
    try {
      await _sendControlMessage(<String, Object?>{
        'type': 'fileOffer',
        'sessionId': sessionId,
        'requestId': requestId,
        'label': selection.label,
        'files': manifest.map((item) => item.toJson()).toList(growable: false),
      });
      final receiverPort = await portCompleter.future.timeout(
        const Duration(seconds: 20),
      );
      final totalBytes = sources.fold<int>(
        0,
        (sum, file) => sum + file.sizeBytes,
      );
      await _fileTransferService.sendFiles(
        host: peer.host,
        port: receiverPort,
        requestId: requestId,
        files: sources,
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
        const NearbyTransferTransferCompletedEvent(
          direction: NearbyTransferProgressDirection.sending,
          message: 'Файлы отправлены.',
        ),
      );
    } finally {
      _pendingSenderPorts.remove(requestId);
    }
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
      final sequence = (json['emojiSequence'] as List<dynamic>?)
          ?.whereType<String>()
          .toList(growable: false);
      if (sequence != null && sequence.isNotEmpty) {
        _events.add(NearbyTransferHandshakeOfferEvent(emojiSequence: sequence));
      }
      return;
    }
    if (type == 'handshakeAccepted') {
      _events.add(const NearbyTransferHandshakeAcceptedEvent());
      return;
    }
    if (type == 'fileOffer') {
      await _handleFileOffer(json);
      return;
    }
    if (type == 'fileReceiverReady') {
      final requestId = json['requestId'] as String?;
      final port = (json['port'] as num?)?.toInt();
      if (requestId != null && port != null) {
        _pendingSenderPorts.remove(requestId)?.complete(port);
      }
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

  Future<void> _handleFileOffer(Map<String, dynamic> json) async {
    final socket = _activeSocket;
    final sessionId = json['sessionId'] as String?;
    final requestId = json['requestId'] as String?;
    final rawFiles = json['files'];
    if (socket == null ||
        _sessionId == null ||
        sessionId != _sessionId ||
        requestId == null ||
        rawFiles is! List<dynamic>) {
      return;
    }

    final items = rawFiles
        .whereType<Map<String, dynamic>>()
        .map(TransferFileManifestItem.fromJson)
        .toList(growable: false);
    if (items.isEmpty) {
      return;
    }

    final destinationDirectory = await _storageService
        .resolveReceiveDirectory();
    final receiveSession = await _fileTransferService.startReceiver(
      requestId: requestId,
      expectedItems: items,
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
    });

    unawaited(
      receiveSession.result.then((result) {
        _receiveSessions.remove(requestId);
        if (result.success) {
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
}

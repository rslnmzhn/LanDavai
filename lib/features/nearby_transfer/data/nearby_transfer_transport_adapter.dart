import 'dart:async';

enum NearbyTransferMode { wifiDirect, lanFallback }

enum NearbyTransferRole { send, receive }

enum NearbyTransferProgressDirection { sending, receiving }

class NearbyTransferCandidateDevice {
  const NearbyTransferCandidateDevice({
    required this.id,
    required this.deviceId,
    required this.displayName,
    required this.host,
    this.port,
  });

  final String id;
  final String deviceId;
  final String displayName;
  final String host;
  final int? port;
}

class NearbyTransferPeerDevice {
  const NearbyTransferPeerDevice({
    required this.deviceId,
    required this.displayName,
    required this.host,
  });

  final String deviceId;
  final String displayName;
  final String host;
}

class NearbyTransferHostingInfo {
  const NearbyTransferHostingInfo({
    required this.port,
    required this.supportsVisibleCandidatePairing,
  });

  final int port;
  final bool supportsVisibleCandidatePairing;
}

class NearbyTransferPickedEntry {
  const NearbyTransferPickedEntry({
    required this.sourcePath,
    required this.relativePath,
    required this.sizeBytes,
  });

  final String sourcePath;
  final String relativePath;
  final int sizeBytes;
}

class NearbyTransferSelection {
  const NearbyTransferSelection({required this.label, required this.entries});

  final String label;
  final List<NearbyTransferPickedEntry> entries;

  int get itemCount => entries.length;
}

abstract class NearbyTransferTransportEvent {
  const NearbyTransferTransportEvent();
}

class NearbyTransferConnectedEvent extends NearbyTransferTransportEvent {
  const NearbyTransferConnectedEvent({
    required this.peer,
    required this.sessionId,
  });

  final NearbyTransferPeerDevice peer;
  final String sessionId;
}

class NearbyTransferDisconnectedEvent extends NearbyTransferTransportEvent {
  const NearbyTransferDisconnectedEvent({this.message});

  final String? message;
}

class NearbyTransferHandshakeOfferEvent extends NearbyTransferTransportEvent {
  const NearbyTransferHandshakeOfferEvent({required this.emojiSequence});

  final List<String> emojiSequence;
}

class NearbyTransferHandshakeAcceptedEvent
    extends NearbyTransferTransportEvent {
  const NearbyTransferHandshakeAcceptedEvent();
}

class NearbyTransferTransferProgressEvent extends NearbyTransferTransportEvent {
  const NearbyTransferTransferProgressEvent({
    required this.direction,
    required this.completedBytes,
    required this.totalBytes,
  });

  final NearbyTransferProgressDirection direction;
  final int completedBytes;
  final int totalBytes;
}

class NearbyTransferTransferCompletedEvent
    extends NearbyTransferTransportEvent {
  const NearbyTransferTransferCompletedEvent({
    required this.direction,
    required this.message,
    this.savedPaths = const <String>[],
  });

  final NearbyTransferProgressDirection direction;
  final String message;
  final List<String> savedPaths;
}

class NearbyTransferErrorEvent extends NearbyTransferTransportEvent {
  const NearbyTransferErrorEvent({required this.message});

  final String message;
}

abstract class NearbyTransferTransportAdapter {
  bool get isSupported;

  int? get visibleCandidatePort;

  Stream<NearbyTransferTransportEvent> get events;

  Future<NearbyTransferHostingInfo> startHostingSession({
    required String sessionId,
    required String localDeviceId,
    required String localDeviceName,
  });

  Future<void> connectToSession({
    required String host,
    required int port,
    required String localDeviceId,
    required String localDeviceName,
    String? expectedSessionId,
  });

  Future<void> sendHandshakeOffer(List<String> emojiSequence);

  Future<void> sendHandshakeAccepted();

  Future<void> sendSelection(NearbyTransferSelection selection);

  Future<void> disconnect();

  void dispose();
}

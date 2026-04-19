import 'dart:async';

enum NearbyTransferMode { wifiDirect, lanFallback }

enum NearbyTransferRole { send, receive }

enum NearbyTransferProgressDirection { sending, receiving }

enum NearbyTransferRemotePreviewKind { none, text, image }

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

class NearbyTransferRemoteFileDescriptor {
  const NearbyTransferRemoteFileDescriptor({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.sizeBytes,
    required this.previewKind,
  });

  final String id;
  final String name;
  final String relativePath;
  final int sizeBytes;
  final NearbyTransferRemotePreviewKind previewKind;
}

enum NearbyTransferRemoteOfferNodeKind { file, directory }

class NearbyTransferRemoteOfferNode {
  const NearbyTransferRemoteOfferNode({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.kind,
    required this.sizeBytes,
    required this.previewKind,
    this.children = const <NearbyTransferRemoteOfferNode>[],
  });

  final String id;
  final String name;
  final String relativePath;
  final NearbyTransferRemoteOfferNodeKind kind;
  final int sizeBytes;
  final NearbyTransferRemotePreviewKind previewKind;
  final List<NearbyTransferRemoteOfferNode> children;

  bool get isDirectory => kind == NearbyTransferRemoteOfferNodeKind.directory;

  bool get isFile => kind == NearbyTransferRemoteOfferNodeKind.file;

  int get fileCount {
    if (isFile) {
      return 1;
    }
    return children.fold<int>(0, (sum, child) => sum + child.fileCount);
  }

  NearbyTransferRemoteFileDescriptor? get asFileDescriptor {
    if (!isFile) {
      return null;
    }
    return NearbyTransferRemoteFileDescriptor(
      id: id,
      name: name,
      relativePath: relativePath,
      sizeBytes: sizeBytes,
      previewKind: previewKind,
    );
  }

  List<NearbyTransferRemoteFileDescriptor> flattenFiles() {
    final files = <NearbyTransferRemoteFileDescriptor>[];
    _collectFiles(this, files);
    return List<NearbyTransferRemoteFileDescriptor>.unmodifiable(files);
  }

  static void _collectFiles(
    NearbyTransferRemoteOfferNode node,
    List<NearbyTransferRemoteFileDescriptor> files,
  ) {
    final descriptor = node.asFileDescriptor;
    if (descriptor != null) {
      files.add(descriptor);
      return;
    }
    for (final child in node.children) {
      _collectFiles(child, files);
    }
  }
}

class NearbyTransferRemoteFilePreview {
  const NearbyTransferRemoteFilePreview._({
    required this.requestId,
    required this.fileId,
    required this.kind,
    this.textContent,
    this.imageBytes,
    this.isTruncated = false,
  });

  const NearbyTransferRemoteFilePreview.text({
    required String requestId,
    required String fileId,
    required String textContent,
    required bool isTruncated,
  }) : this._(
         requestId: requestId,
         fileId: fileId,
         kind: NearbyTransferRemotePreviewKind.text,
         textContent: textContent,
         isTruncated: isTruncated,
       );

  const NearbyTransferRemoteFilePreview.image({
    required String requestId,
    required String fileId,
    required List<int> imageBytes,
  }) : this._(
         requestId: requestId,
         fileId: fileId,
         kind: NearbyTransferRemotePreviewKind.image,
         imageBytes: imageBytes,
       );

  final String requestId;
  final String fileId;
  final NearbyTransferRemotePreviewKind kind;
  final String? textContent;
  final List<int>? imageBytes;
  final bool isTruncated;
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
  const NearbyTransferHandshakeOfferEvent({required this.verificationCode});

  final List<String> verificationCode;
}

class NearbyTransferHandshakeAcceptedEvent
    extends NearbyTransferTransportEvent {
  const NearbyTransferHandshakeAcceptedEvent();
}

class NearbyTransferIncomingSelectionOfferedEvent
    extends NearbyTransferTransportEvent {
  const NearbyTransferIncomingSelectionOfferedEvent({
    required this.requestId,
    required this.label,
    required this.roots,
  });

  final String requestId;
  final String label;
  final List<NearbyTransferRemoteOfferNode> roots;

  List<NearbyTransferRemoteFileDescriptor> get files {
    final collected = <NearbyTransferRemoteFileDescriptor>[];
    for (final root in roots) {
      collected.addAll(root.flattenFiles());
    }
    return List<NearbyTransferRemoteFileDescriptor>.unmodifiable(collected);
  }
}

class NearbyTransferSelectionPreparationStartedEvent
    extends NearbyTransferTransportEvent {
  const NearbyTransferSelectionPreparationStartedEvent({
    required this.label,
    required this.totalItemCount,
    required this.totalBytes,
  });

  final String label;
  final int totalItemCount;
  final int totalBytes;
}

class NearbyTransferSelectionPreparationProgressEvent
    extends NearbyTransferTransportEvent {
  const NearbyTransferSelectionPreparationProgressEvent({
    required this.label,
    required this.completedItemCount,
    required this.totalItemCount,
    required this.preparedBytes,
    required this.totalBytes,
    required this.currentRelativePath,
  });

  final String label;
  final int completedItemCount;
  final int totalItemCount;
  final int preparedBytes;
  final int totalBytes;
  final String currentRelativePath;
}

class NearbyTransferSelectionPreparationCompletedEvent
    extends NearbyTransferTransportEvent {
  const NearbyTransferSelectionPreparationCompletedEvent({
    required this.requestId,
    required this.label,
    required this.totalItemCount,
    required this.totalBytes,
  });

  final String requestId;
  final String label;
  final int totalItemCount;
  final int totalBytes;
}

class NearbyTransferRemotePreviewReadyEvent
    extends NearbyTransferTransportEvent {
  const NearbyTransferRemotePreviewReadyEvent({required this.preview});

  final NearbyTransferRemoteFilePreview preview;
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

  Future<void> sendHandshakeOffer(List<String> verificationCode);

  Future<void> sendHandshakeAccepted();

  Future<void> sendSelection(NearbyTransferSelection selection);

  Future<void> requestIncomingSelectionPreview({
    required String requestId,
    required String fileId,
  });

  Future<void> requestIncomingSelectionDownload({
    required String requestId,
    required List<String> fileIds,
  });

  Future<void> disconnect();

  void dispose();
}

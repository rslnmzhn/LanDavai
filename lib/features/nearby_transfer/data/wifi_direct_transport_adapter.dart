import 'dart:async';

import 'nearby_transfer_transport_adapter.dart';

class WifiDirectTransportAdapter implements NearbyTransferTransportAdapter {
  final StreamController<NearbyTransferTransportEvent> _events =
      StreamController<NearbyTransferTransportEvent>.broadcast();

  @override
  bool get isSupported => false;

  @override
  int? get visibleCandidatePort => null;

  @override
  Stream<NearbyTransferTransportEvent> get events => _events.stream;

  @override
  Future<NearbyTransferHostingInfo> startHostingSession({
    required String sessionId,
    required String localDeviceId,
    required String localDeviceName,
  }) async {
    throw UnsupportedError('Wi-Fi Direct transport is not available in v1.');
  }

  @override
  Future<void> connectToSession({
    required String host,
    required int port,
    required String localDeviceId,
    required String localDeviceName,
    String? expectedSessionId,
  }) async {
    throw UnsupportedError('Wi-Fi Direct transport is not available in v1.');
  }

  @override
  Future<void> sendHandshakeOffer(List<String> verificationCode) async {
    throw UnsupportedError('Wi-Fi Direct transport is not available in v1.');
  }

  @override
  Future<void> sendHandshakeAccepted() async {
    throw UnsupportedError('Wi-Fi Direct transport is not available in v1.');
  }

  @override
  Future<void> sendSelection(NearbyTransferSelection selection) async {
    throw UnsupportedError('Wi-Fi Direct transport is not available in v1.');
  }

  @override
  Future<void> requestIncomingSelectionPreview({
    required String requestId,
    required String fileId,
  }) async {
    throw UnsupportedError('Wi-Fi Direct transport is not available in v1.');
  }

  @override
  Future<void> requestIncomingSelectionDownload({
    required String requestId,
    required List<String> fileIds,
  }) async {
    throw UnsupportedError('Wi-Fi Direct transport is not available in v1.');
  }

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() {
    _events.close();
  }
}

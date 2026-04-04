import 'dart:async';

import 'package:landa/features/discovery/application/discovery_read_model.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_candidate_projection.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_availability_store.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_capability_service.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_handshake_service.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_mode_resolver.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_session_store.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_file_picker.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/data/qr_payload_codec.dart';

class FakeNearbyTransferTransportAdapter
    implements NearbyTransferTransportAdapter {
  FakeNearbyTransferTransportAdapter({
    this.supported = true,
    this.visiblePort = 45321,
    this.hostingPort = 45321,
    this.supportsVisibleCandidatePairing = true,
    this.emitDisconnectedOnDisconnect = false,
  });

  final bool supported;
  final int? visiblePort;
  final int hostingPort;
  final bool supportsVisibleCandidatePairing;
  final bool emitDisconnectedOnDisconnect;

  final StreamController<NearbyTransferTransportEvent> _events =
      StreamController<NearbyTransferTransportEvent>.broadcast();

  int startHostingCalls = 0;
  int connectCalls = 0;
  int sendHandshakeOfferCalls = 0;
  int sendHandshakeAcceptedCalls = 0;
  int sendSelectionCalls = 0;
  int disconnectCalls = 0;
  String? lastConnectHost;
  int? lastConnectPort;
  String? lastExpectedSessionId;
  List<String>? lastHandshakeOffer;
  NearbyTransferSelection? lastSelection;
  String? lastHostedSessionId;

  @override
  bool get isSupported => supported;

  @override
  int? get visibleCandidatePort => visiblePort;

  @override
  Stream<NearbyTransferTransportEvent> get events => _events.stream;

  void emit(NearbyTransferTransportEvent event) {
    _events.add(event);
  }

  @override
  Future<NearbyTransferHostingInfo> startHostingSession({
    required String sessionId,
    required String localDeviceId,
    required String localDeviceName,
  }) async {
    startHostingCalls += 1;
    lastHostedSessionId = sessionId;
    return NearbyTransferHostingInfo(
      port: hostingPort,
      supportsVisibleCandidatePairing: supportsVisibleCandidatePairing,
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
    connectCalls += 1;
    lastConnectHost = host;
    lastConnectPort = port;
    lastExpectedSessionId = expectedSessionId;
  }

  @override
  Future<void> sendHandshakeOffer(List<String> emojiSequence) async {
    sendHandshakeOfferCalls += 1;
    lastHandshakeOffer = List<String>.unmodifiable(emojiSequence);
  }

  @override
  Future<void> sendHandshakeAccepted() async {
    sendHandshakeAcceptedCalls += 1;
  }

  @override
  Future<void> sendSelection(NearbyTransferSelection selection) async {
    sendSelectionCalls += 1;
    lastSelection = selection;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
    if (emitDisconnectedOnDisconnect) {
      emit(
        const NearbyTransferDisconnectedEvent(message: 'Соединение закрыто.'),
      );
    }
  }

  @override
  void dispose() {
    _events.close();
  }
}

class StubNearbyTransferFilePicker extends NearbyTransferFilePicker {
  StubNearbyTransferFilePicker({
    this.directoryPickingSupported = true,
    this.fileSelection,
    this.directorySelection,
  });

  final bool directoryPickingSupported;
  final NearbyTransferSelection? fileSelection;
  final NearbyTransferSelection? directorySelection;

  @override
  bool get supportsDirectoryPicking => directoryPickingSupported;

  @override
  Future<NearbyTransferSelection?> pickFiles() async => fileSelection;

  @override
  Future<NearbyTransferSelection?> pickDirectory() async => directorySelection;
}

NearbyTransferSessionStore buildTestNearbyTransferStore({
  required DiscoveryReadModel readModel,
  FakeNearbyTransferTransportAdapter? wifiAdapter,
  FakeNearbyTransferTransportAdapter? lanAdapter,
  NearbyTransferFilePicker? filePicker,
  bool wifiDirectSupported = false,
  Duration candidateRefreshInterval = const Duration(seconds: 2),
  String localDeviceId = 'aa:bb:cc:dd:ee:ff',
  String localDeviceName = 'Test device',
  String? localIp = '192.168.0.10',
  NearbyTransferAvailabilityStore? availabilityStore,
}) {
  return NearbyTransferSessionStore(
    capabilityService: NearbyTransferCapabilityService(
      wifiDirectSupported: wifiDirectSupported,
    ),
    modeResolver: const NearbyTransferModeResolver(),
    handshakeService: NearbyTransferHandshakeService(),
    candidateProjection: NearbyTransferCandidateProjection(
      readModel: readModel,
    ),
    availabilityStore: availabilityStore ?? NearbyTransferAvailabilityStore(),
    qrCodec: const NearbyTransferQrCodec(),
    wifiDirectTransportAdapter:
        wifiAdapter ?? FakeNearbyTransferTransportAdapter(),
    lanNearbyTransportAdapter:
        lanAdapter ?? FakeNearbyTransferTransportAdapter(),
    filePicker: filePicker ?? StubNearbyTransferFilePicker(),
    localDeviceIdProvider: () => localDeviceId,
    localDeviceNameProvider: () => localDeviceName,
    localIpProvider: () => localIp,
    candidateRefreshInterval: candidateRefreshInterval,
  );
}

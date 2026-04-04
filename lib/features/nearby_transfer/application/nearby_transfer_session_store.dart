import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/nearby_transfer_file_picker.dart';
import '../data/nearby_transfer_transport_adapter.dart';
import '../data/qr_payload_codec.dart';
import 'nearby_transfer_candidate_projection.dart';
import 'nearby_transfer_capability_service.dart';
import 'nearby_transfer_handshake_service.dart';
import 'nearby_transfer_mode_resolver.dart';

enum NearbyTransferSessionPhase {
  idle,
  waitingForPeer,
  connecting,
  awaitingHandshake,
  connected,
  transferring,
}

class NearbyTransferSessionStore extends ChangeNotifier {
  NearbyTransferSessionStore({
    required NearbyTransferCapabilityService capabilityService,
    required NearbyTransferModeResolver modeResolver,
    required NearbyTransferHandshakeService handshakeService,
    required NearbyTransferCandidateProjection candidateProjection,
    required NearbyTransferQrCodec qrCodec,
    required NearbyTransferTransportAdapter wifiDirectTransportAdapter,
    required NearbyTransferTransportAdapter lanNearbyTransportAdapter,
    required NearbyTransferFilePicker filePicker,
    required String Function() localDeviceIdProvider,
    required String Function() localDeviceNameProvider,
    required String? Function() localIpProvider,
    Duration candidateRefreshInterval = const Duration(seconds: 2),
  }) : _capabilityService = capabilityService,
       _modeResolver = modeResolver,
       _handshakeService = handshakeService,
       _candidateProjection = candidateProjection,
       _qrCodec = qrCodec,
       _wifiDirectTransportAdapter = wifiDirectTransportAdapter,
       _lanNearbyTransportAdapter = lanNearbyTransportAdapter,
       _filePicker = filePicker,
       _localDeviceIdProvider = localDeviceIdProvider,
       _localDeviceNameProvider = localDeviceNameProvider,
       _localIpProvider = localIpProvider,
       _candidateRefreshInterval = candidateRefreshInterval {
    _resetSessionIdentity();
  }

  final NearbyTransferCapabilityService _capabilityService;
  final NearbyTransferModeResolver _modeResolver;
  final NearbyTransferHandshakeService _handshakeService;
  final NearbyTransferCandidateProjection _candidateProjection;
  final NearbyTransferQrCodec _qrCodec;
  final NearbyTransferTransportAdapter _wifiDirectTransportAdapter;
  final NearbyTransferTransportAdapter _lanNearbyTransportAdapter;
  final NearbyTransferFilePicker _filePicker;
  final String Function() _localDeviceIdProvider;
  final String Function() _localDeviceNameProvider;
  final String? Function() _localIpProvider;
  final Duration _candidateRefreshInterval;

  StreamSubscription<NearbyTransferTransportEvent>? _transportSubscription;
  Timer? _candidateRefreshTimer;

  NearbyTransferMode? _mode;
  NearbyTransferRole? _role;
  NearbyTransferSessionPhase _phase = NearbyTransferSessionPhase.idle;
  NearbyTransferCapabilitySnapshot? _capabilities;
  NearbyTransferPeerDevice? _peer;
  List<NearbyTransferCandidateDevice> _candidateDevices =
      const <NearbyTransferCandidateDevice>[];
  String? _selectedCandidateId;
  String? _bannerMessage;
  bool _bannerIsError = false;
  String? _qrPayloadText;
  String? _sessionId;
  List<String> _emojiSequence = const <String>[];
  NearbyTransferHandshakeChallenge? _handshakeChallenge;
  int _transferCompletedBytes = 0;
  int _transferTotalBytes = 0;
  bool _hasCompletedOutgoingTransfer = false;
  bool _disposed = false;

  NearbyTransferMode? get mode => _mode;

  NearbyTransferRole? get role => _role;

  NearbyTransferSessionPhase get phase => _phase;

  NearbyTransferPeerDevice? get peer => _peer;

  List<NearbyTransferCandidateDevice> get candidateDevices =>
      List<NearbyTransferCandidateDevice>.unmodifiable(_candidateDevices);

  String? get selectedCandidateId => _selectedCandidateId;

  String? get bannerMessage => _bannerMessage;

  bool get bannerIsError => _bannerIsError;

  String? get qrPayloadText => _qrPayloadText;

  List<String> get emojiSequence => List<String>.unmodifiable(_emojiSequence);

  NearbyTransferHandshakeChallenge? get handshakeChallenge =>
      _handshakeChallenge;

  bool get liveQrScannerSupported =>
      _capabilities?.liveQrScannerSupported ?? false;

  bool get hasActiveConnection =>
      _peer != null ||
      _phase == NearbyTransferSessionPhase.connecting ||
      _phase == NearbyTransferSessionPhase.awaitingHandshake ||
      _phase == NearbyTransferSessionPhase.connected ||
      _phase == NearbyTransferSessionPhase.transferring;

  bool get canSendFiles =>
      _role == NearbyTransferRole.send &&
      (_phase == NearbyTransferSessionPhase.connected);

  bool get canSendDirectory =>
      canSendFiles && _filePicker.supportsDirectoryPicking;

  bool get shouldShowSendMore =>
      _role == NearbyTransferRole.send && _hasCompletedOutgoingTransfer;

  double? get transferProgress {
    if (_transferTotalBytes <= 0) {
      return null;
    }
    return (_transferCompletedBytes / _transferTotalBytes).clamp(0.0, 1.0);
  }

  String get modeLabel => switch (_mode) {
    NearbyTransferMode.wifiDirect => 'Wi-Fi Direct',
    NearbyTransferMode.lanFallback => 'Локальная сеть',
    null => 'Подготовка',
  };

  Future<void> prepareSendFlow() async {
    await _prepareRole(NearbyTransferRole.send);
    final adapter = _activeAdapter;
    if (adapter == null) {
      return;
    }

    final hostingInfo = await adapter.startHostingSession(
      sessionId: _sessionId!,
      localDeviceId: _localDeviceIdProvider(),
      localDeviceName: _localDeviceNameProvider(),
    );
    _phase = NearbyTransferSessionPhase.waitingForPeer;
    if (_mode == NearbyTransferMode.lanFallback) {
      final host = _localIpProvider();
      if (host == null || host.trim().isEmpty) {
        _setBanner('Не удалось определить локальный IP для QR.', isError: true);
      } else {
        final payload = NearbyTransferQrPayload(
          deviceId: _localDeviceIdProvider(),
          sessionId: _sessionId!,
          transportMode: NearbyTransferMode.lanFallback,
          transportInfo: <String, Object?>{
            'host': host.trim(),
            'port': hostingInfo.port,
            'sessionId': _sessionId!,
          },
        );
        _qrPayloadText = _qrCodec.encode(payload);
      }
      if (!hostingInfo.supportsVisibleCandidatePairing) {
        _setBanner(
          'Подключение по списку устройств может быть недоступно. Используйте QR.',
        );
      }
      await refreshCandidates();
      _startCandidateRefreshTimer();
    }
    notifyListeners();
  }

  Future<void> prepareReceiveFlow() async {
    await _prepareRole(NearbyTransferRole.receive);
    if (_mode == NearbyTransferMode.lanFallback) {
      await refreshCandidates();
      _startCandidateRefreshTimer();
    }
    notifyListeners();
  }

  Future<void> refreshCandidates() async {
    if (_mode != NearbyTransferMode.lanFallback) {
      return;
    }
    _candidateDevices = _candidateProjection.snapshotCandidates();
    if (_selectedCandidateId != null &&
        _candidateDevices.every(
          (candidate) => candidate.id != _selectedCandidateId,
        )) {
      _selectedCandidateId = null;
    }
    notifyListeners();
  }

  Future<void> connectToCandidate(
    NearbyTransferCandidateDevice candidate,
  ) async {
    final adapter = _activeAdapter;
    final port = adapter?.visibleCandidatePort;
    if (_mode != NearbyTransferMode.lanFallback ||
        adapter == null ||
        port == null) {
      return;
    }
    _selectedCandidateId = candidate.id;
    _phase = NearbyTransferSessionPhase.connecting;
    notifyListeners();
    await adapter.connectToSession(
      host: candidate.host,
      port: port,
      localDeviceId: _localDeviceIdProvider(),
      localDeviceName: _localDeviceNameProvider(),
    );
  }

  Future<void> handleQrPayloadText(String rawPayload) async {
    final payload = _qrCodec.decode(rawPayload);
    if (payload == null ||
        payload.transportMode != NearbyTransferMode.lanFallback) {
      return;
    }

    final host = payload.transportInfo['host'] as String?;
    final port = (payload.transportInfo['port'] as num?)?.toInt();
    final sessionId = payload.transportInfo['sessionId'] as String?;
    if (host == null || port == null || sessionId == null) {
      return;
    }
    final adapter = _activeAdapter;
    if (adapter == null) {
      return;
    }
    _phase = NearbyTransferSessionPhase.connecting;
    notifyListeners();
    await adapter.connectToSession(
      host: host,
      port: port,
      localDeviceId: _localDeviceIdProvider(),
      localDeviceName: _localDeviceNameProvider(),
      expectedSessionId: sessionId,
    );
  }

  Future<void> selectHandshakeChoice(List<String> choice) async {
    final expectedSequence = _emojiSequence;
    if (expectedSequence.isEmpty) {
      return;
    }
    final isValid = _handshakeService.isValidChoice(
      expectedSequence: expectedSequence,
      selectedChoice: choice,
    );
    if (!isValid) {
      _setBanner('Эмодзи не совпали. Попробуйте ещё раз.', isError: true);
      return;
    }

    await _activeAdapter?.sendHandshakeAccepted();
    _phase = NearbyTransferSessionPhase.connected;
    _setBanner('Соединение подтверждено.');
    notifyListeners();
  }

  Future<void> sendFiles() async {
    final selection = await _filePicker.pickFiles();
    if (selection == null) {
      return;
    }
    await _sendSelection(selection);
  }

  Future<void> sendDirectory() async {
    final selection = await _filePicker.pickDirectory();
    if (selection == null) {
      return;
    }
    await _sendSelection(selection);
  }

  Future<void> disconnect({bool restart = true}) async {
    await _activeAdapter?.disconnect();
    _clearConnectionState();
    if (!restart || _role == null) {
      _phase = NearbyTransferSessionPhase.idle;
      notifyListeners();
      return;
    }

    _resetSessionIdentity();
    if (_role == NearbyTransferRole.send) {
      await prepareSendFlow();
      return;
    }
    await prepareReceiveFlow();
  }

  Future<void> resetForEntrySelection() async {
    await _activeAdapter?.disconnect();
    _clearConnectionState();
    _candidateDevices = const <NearbyTransferCandidateDevice>[];
    _mode = null;
    _role = null;
    _phase = NearbyTransferSessionPhase.idle;
    _bannerMessage = null;
    _bannerIsError = false;
    _qrPayloadText = null;
    _resetSessionIdentity();
    notifyListeners();
  }

  Future<void> _prepareRole(NearbyTransferRole nextRole) async {
    _role = nextRole;
    _clearConnectionState();
    final capabilities = _capabilityService.snapshot();
    _capabilities = capabilities;
    _mode = _modeResolver.resolve(capabilities);
    _setBanner(
      _mode == NearbyTransferMode.wifiDirect
          ? 'Используется Wi-Fi Direct.'
          : 'Wi-Fi Direct недоступен. Используется локальная сеть.',
    );
    await _subscribeToActiveAdapter();
  }

  NearbyTransferTransportAdapter? get _activeAdapter => switch (_mode) {
    NearbyTransferMode.wifiDirect => _wifiDirectTransportAdapter,
    NearbyTransferMode.lanFallback => _lanNearbyTransportAdapter,
    null => null,
  };

  Future<void> _subscribeToActiveAdapter() async {
    await _transportSubscription?.cancel();
    _transportSubscription = _activeAdapter?.events.listen(
      (event) => unawaited(_handleTransportEvent(event)),
    );
  }

  Future<void> _handleTransportEvent(NearbyTransferTransportEvent event) async {
    if (event is NearbyTransferConnectedEvent) {
      _peer = event.peer;
      _sessionId = event.sessionId;
      _phase = NearbyTransferSessionPhase.awaitingHandshake;
      if (_role == NearbyTransferRole.send) {
        await _activeAdapter?.sendHandshakeOffer(_emojiSequence);
        _setBanner('Подтвердите эмодзи на втором устройстве.');
      }
      notifyListeners();
      return;
    }
    if (event is NearbyTransferHandshakeOfferEvent) {
      _emojiSequence = List<String>.unmodifiable(event.emojiSequence);
      _handshakeChallenge = _handshakeService.buildChallenge(
        event.emojiSequence,
      );
      _phase = NearbyTransferSessionPhase.awaitingHandshake;
      _setBanner('Выберите совпадающий набор эмодзи.');
      notifyListeners();
      return;
    }
    if (event is NearbyTransferHandshakeAcceptedEvent) {
      _phase = NearbyTransferSessionPhase.connected;
      _handshakeChallenge = null;
      _setBanner('Соединение подтверждено.');
      notifyListeners();
      return;
    }
    if (event is NearbyTransferTransferProgressEvent) {
      _transferCompletedBytes = event.completedBytes;
      _transferTotalBytes = event.totalBytes;
      _phase = NearbyTransferSessionPhase.transferring;
      notifyListeners();
      return;
    }
    if (event is NearbyTransferTransferCompletedEvent) {
      _phase = NearbyTransferSessionPhase.connected;
      _transferCompletedBytes = 0;
      _transferTotalBytes = 0;
      if (event.direction == NearbyTransferProgressDirection.sending) {
        _hasCompletedOutgoingTransfer = true;
      }
      _setBanner(event.message);
      notifyListeners();
      return;
    }
    if (event is NearbyTransferDisconnectedEvent) {
      _clearConnectionState();
      _phase = _role == NearbyTransferRole.send
          ? NearbyTransferSessionPhase.waitingForPeer
          : NearbyTransferSessionPhase.idle;
      _setBanner(event.message ?? 'Соединение закрыто.');
      notifyListeners();
      return;
    }
    if (event is NearbyTransferErrorEvent) {
      _setBanner(event.message, isError: true);
      notifyListeners();
    }
  }

  Future<void> _sendSelection(NearbyTransferSelection selection) async {
    if (!canSendFiles) {
      return;
    }
    _phase = NearbyTransferSessionPhase.transferring;
    notifyListeners();
    await _activeAdapter?.sendSelection(selection);
  }

  void _startCandidateRefreshTimer() {
    _candidateRefreshTimer?.cancel();
    if (_mode != NearbyTransferMode.lanFallback) {
      return;
    }
    _candidateRefreshTimer = Timer.periodic(_candidateRefreshInterval, (_) {
      unawaited(refreshCandidates());
    });
  }

  void _resetSessionIdentity() {
    _sessionId = 'nearby-${DateTime.now().microsecondsSinceEpoch}';
    _emojiSequence = _handshakeService.createEmojiSequence();
    _handshakeChallenge = null;
    _qrPayloadText = null;
    _hasCompletedOutgoingTransfer = false;
  }

  void _clearConnectionState() {
    _peer = null;
    _handshakeChallenge = null;
    _transferCompletedBytes = 0;
    _transferTotalBytes = 0;
    _selectedCandidateId = null;
    _candidateRefreshTimer?.cancel();
    _candidateRefreshTimer = null;
  }

  void _setBanner(String? message, {bool isError = false}) {
    _bannerMessage = message;
    _bannerIsError = isError;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _candidateRefreshTimer?.cancel();
    _transportSubscription?.cancel();
    _wifiDirectTransportAdapter.dispose();
    _lanNearbyTransportAdapter.dispose();
    super.dispose();
  }
}

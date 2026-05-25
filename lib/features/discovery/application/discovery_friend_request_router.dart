import 'dart:async';

import '../../transfer/data/file_hash_service.dart';
import '../data/device_alias_repository.dart';
import '../data/lan_discovery_service.dart';
import '../data/lan_protocol_events.dart';
import '../domain/discovered_device.dart';

class IncomingFriendRequest {
  const IncomingFriendRequest({
    required this.requestId,
    required this.senderIp,
    required this.senderName,
    required this.senderMacAddress,
    required this.createdAt,
  });

  final String requestId;
  final String senderIp;
  final String senderName;
  final String senderMacAddress;
  final DateTime createdAt;
}

class DiscoveryFriendRequestResult {
  const DiscoveryFriendRequestResult({this.infoMessage, this.errorMessage});

  final String? infoMessage;
  final String? errorMessage;
}

class DiscoveryFriendIncomingResult {
  const DiscoveryFriendIncomingResult({
    this.infoMessage,
    this.shouldNotifyListeners = false,
  });

  final String? infoMessage;
  final bool shouldNotifyListeners;
}

class DiscoveryFriendRequestRouter {
  DiscoveryFriendRequestRouter({
    required LanDiscoveryService lanDiscoveryService,
    required FileHashService fileHashService,
    required String Function() localNameProvider,
    required String Function() localDeviceMacProvider,
    required bool Function(String? macAddress) isTrustedMac,
    required DiscoveredDevice? Function(String ip) deviceByIp,
    required Future<void> Function({
      required String ip,
      required String macAddress,
      required String deviceName,
      required DateTime observedAt,
      String? peerId,
    })
    rememberVisibleFriendPeer,
    required Future<void> Function({
      required String macAddress,
      required bool isFriend,
    })
    setFriendStatus,
    required Future<void> Function(String requesterName)
    showFriendRequestNotification,
    required void Function(String message) log,
    DateTime Function()? nowProvider,
    Duration pendingFriendRequestTtl = const Duration(minutes: 2),
  }) : _lanDiscoveryService = lanDiscoveryService,
       _fileHashService = fileHashService,
       _localNameProvider = localNameProvider,
       _localDeviceMacProvider = localDeviceMacProvider,
       _isTrustedMac = isTrustedMac,
       _deviceByIp = deviceByIp,
       _rememberVisibleFriendPeer = rememberVisibleFriendPeer,
       _setFriendStatus = setFriendStatus,
       _showFriendRequestNotification = showFriendRequestNotification,
       _log = log,
       _now = nowProvider ?? DateTime.now,
       _pendingFriendRequestTtl = pendingFriendRequestTtl;

  final LanDiscoveryService _lanDiscoveryService;
  final FileHashService _fileHashService;
  final String Function() _localNameProvider;
  final String Function() _localDeviceMacProvider;
  final bool Function(String? macAddress) _isTrustedMac;
  final DiscoveredDevice? Function(String ip) _deviceByIp;
  final Future<void> Function({
    required String ip,
    required String macAddress,
    required String deviceName,
    required DateTime observedAt,
    String? peerId,
  })
  _rememberVisibleFriendPeer;
  final Future<void> Function({
    required String macAddress,
    required bool isFriend,
  })
  _setFriendStatus;
  final Future<void> Function(String requesterName)
  _showFriendRequestNotification;
  final void Function(String message) _log;
  final DateTime Function() _now;
  final Duration _pendingFriendRequestTtl;

  final List<IncomingFriendRequest> _incomingFriendRequests =
      <IncomingFriendRequest>[];
  final Map<String, _PendingOutgoingFriendRequest>
  _pendingOutgoingFriendRequestsByRequestId =
      <String, _PendingOutgoingFriendRequest>{};

  List<IncomingFriendRequest> get incomingFriendRequests =>
      List<IncomingFriendRequest>.unmodifiable(_incomingFriendRequests);

  bool hasPendingFriendRequestForDevice(DiscoveredDevice device) {
    purgeExpiredPendingFriendRequests();
    final mac = DeviceAliasRepository.normalizeMac(device.macAddress);
    if (mac == null) {
      return false;
    }
    return _pendingOutgoingFriendRequestsByRequestId.values.any(
      (pending) => pending.targetMacAddress == mac,
    );
  }

  Future<DiscoveryFriendRequestResult> sendFriendRequest(
    DiscoveredDevice device,
  ) async {
    if (!device.isAppDetected) {
      return const DiscoveryFriendRequestResult(
        errorMessage: 'Friend request is available only for Landa devices.',
      );
    }

    final mac = DeviceAliasRepository.normalizeMac(device.macAddress);
    if (mac == null) {
      return const DiscoveryFriendRequestResult(
        errorMessage: 'Cannot send friend request until MAC address is known.',
      );
    }

    if (_isTrustedMac(mac)) {
      return DiscoveryFriendRequestResult(
        infoMessage: '${device.displayName} is already in your friends list.',
      );
    }

    purgeExpiredPendingFriendRequests();
    final alreadyPending = _pendingOutgoingFriendRequestsByRequestId.values.any(
      (pending) => pending.targetMacAddress == mac,
    );
    if (alreadyPending) {
      return DiscoveryFriendRequestResult(
        infoMessage: 'Friend request already sent to ${device.displayName}.',
      );
    }

    final localDeviceMac = _localDeviceMacProvider();
    final requestId = _fileHashService.buildStableId(
      'friend-request|${_now().microsecondsSinceEpoch}|$mac|$localDeviceMac',
    );

    try {
      await _lanDiscoveryService.sendFriendRequest(
        targetIp: device.ip,
        requestId: requestId,
        requesterName: _localNameProvider(),
        requesterMacAddress: localDeviceMac,
      );
      _pendingOutgoingFriendRequestsByRequestId[requestId] =
          _PendingOutgoingFriendRequest(
            targetName: device.displayName,
            targetMacAddress: mac,
            createdAt: _now(),
          );
      return DiscoveryFriendRequestResult(
        infoMessage: 'Friend request sent to ${device.displayName}.',
      );
    } catch (error) {
      final message = 'Failed to send friend request: $error';
      _log(message);
      return DiscoveryFriendRequestResult(errorMessage: message);
    }
  }

  Future<DiscoveryFriendRequestResult> respondToFriendRequest({
    required String requestId,
    required bool accept,
  }) async {
    final index = _incomingFriendRequests.indexWhere(
      (request) => request.requestId == requestId,
    );
    if (index < 0) {
      return const DiscoveryFriendRequestResult();
    }

    final request = _incomingFriendRequests[index];
    _incomingFriendRequests.removeAt(index);

    try {
      if (accept) {
        await _rememberVisibleFriendPeer(
          ip: request.senderIp,
          macAddress: request.senderMacAddress,
          deviceName: request.senderName,
          observedAt: request.createdAt,
        );
        await _setFriendStatus(
          macAddress: request.senderMacAddress,
          isFriend: true,
        );
      }

      await _lanDiscoveryService.sendFriendResponse(
        targetIp: request.senderIp,
        requestId: request.requestId,
        responderName: _localNameProvider(),
        responderMacAddress: _localDeviceMacProvider(),
        accepted: accept,
      );
      return DiscoveryFriendRequestResult(
        infoMessage: accept
            ? '${request.senderName} added to friends.'
            : 'Friend request from ${request.senderName} declined.',
      );
    } catch (error) {
      final message = 'Failed to process friend request: $error';
      _log(message);
      return DiscoveryFriendRequestResult(errorMessage: message);
    }
  }

  DiscoveryFriendIncomingResult handleFriendRequest(FriendRequestEvent event) {
    final normalizedSenderMac = DeviceAliasRepository.normalizeMac(
      event.requesterMacAddress,
    );
    if (normalizedSenderMac == null) {
      _log(
        'Ignoring friend request with invalid MAC from ${event.requesterIp}',
      );
      return const DiscoveryFriendIncomingResult();
    }

    if (normalizedSenderMac == _localDeviceMacProvider()) {
      return const DiscoveryFriendIncomingResult();
    }

    final senderDevice = _deviceByIp(event.requesterIp);
    final senderName = senderDevice?.displayName ?? event.requesterName;

    if (_isTrustedMac(normalizedSenderMac)) {
      unawaited(
        _rememberVisibleFriendPeer(
          ip: event.requesterIp,
          macAddress: normalizedSenderMac,
          deviceName: senderName,
          observedAt: event.observedAt,
        ),
      );
      _log('Friend request from known friend $senderName. Auto-accepting.');
      unawaited(
        _lanDiscoveryService.sendFriendResponse(
          targetIp: event.requesterIp,
          requestId: event.requestId,
          responderName: _localNameProvider(),
          responderMacAddress: _localDeviceMacProvider(),
          accepted: true,
        ),
      );
      return const DiscoveryFriendIncomingResult(shouldNotifyListeners: true);
    }

    unawaited(
      _rememberVisibleFriendPeer(
        ip: event.requesterIp,
        macAddress: normalizedSenderMac,
        deviceName: senderName,
        observedAt: event.observedAt,
      ),
    );
    _incomingFriendRequests.removeWhere(
      (request) =>
          request.requestId == event.requestId ||
          request.senderMacAddress == normalizedSenderMac,
    );
    _incomingFriendRequests.insert(
      0,
      IncomingFriendRequest(
        requestId: event.requestId,
        senderIp: event.requesterIp,
        senderName: senderName,
        senderMacAddress: normalizedSenderMac,
        createdAt: event.observedAt,
      ),
    );

    unawaited(_showFriendRequestNotification(senderName));
    return DiscoveryFriendIncomingResult(
      infoMessage: 'New friend request from $senderName.',
      shouldNotifyListeners: true,
    );
  }

  Future<DiscoveryFriendRequestResult> acceptFriendResponse(
    FriendResponseEvent event,
  ) async {
    purgeExpiredPendingFriendRequests();
    final pending = _pendingOutgoingFriendRequestsByRequestId.remove(
      event.requestId,
    );
    if (pending == null) {
      return const DiscoveryFriendRequestResult();
    }

    final responderMac = DeviceAliasRepository.normalizeMac(
      event.responderMacAddress,
    );
    final responderName = event.responderName.trim().isEmpty
        ? pending.targetName
        : event.responderName;

    if (!event.accepted) {
      return DiscoveryFriendRequestResult(
        infoMessage: '$responderName declined your friend request.',
      );
    }

    if (responderMac == null) {
      return const DiscoveryFriendRequestResult(
        errorMessage: 'Friend request accepted, but responder MAC is invalid.',
      );
    }

    try {
      if (event.responderIp.isNotEmpty) {
        await _rememberVisibleFriendPeer(
          ip: event.responderIp,
          macAddress: responderMac,
          deviceName: responderName,
          observedAt: event.observedAt,
        );
      }
      await _setFriendStatus(macAddress: responderMac, isFriend: true);
      return DiscoveryFriendRequestResult(
        infoMessage: '$responderName accepted your friend request.',
      );
    } catch (error) {
      final message = 'Failed to save accepted friend: $error';
      _log(message);
      return DiscoveryFriendRequestResult(errorMessage: message);
    }
  }

  void purgeExpiredPendingFriendRequests() {
    final now = _now();
    _pendingOutgoingFriendRequestsByRequestId.removeWhere(
      (_, pending) =>
          now.difference(pending.createdAt) > _pendingFriendRequestTtl,
    );
  }
}

class _PendingOutgoingFriendRequest {
  const _PendingOutgoingFriendRequest({
    required this.targetName,
    required this.targetMacAddress,
    required this.createdAt,
  });

  final String targetName;
  final String targetMacAddress;
  final DateTime createdAt;
}

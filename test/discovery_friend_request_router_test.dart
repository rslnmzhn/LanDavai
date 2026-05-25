import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/discovery_friend_request_router.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';

void main() {
  group('DiscoveryFriendRequestRouter', () {
    test(
      'sends one outgoing request and reports duplicate pending state',
      () async {
        final service = _RecordingLanDiscoveryService();
        final router = _buildRouter(lanDiscoveryService: service);
        final device = DiscoveredDevice(
          ip: '192.168.1.10',
          macAddress: 'AA-BB-CC-DD-EE-FF',
          deviceName: 'Alice',
          isAppDetected: true,
          lastSeen: DateTime(2026),
        );

        final first = await router.sendFriendRequest(device);
        final duplicate = await router.sendFriendRequest(device);

        expect(first.errorMessage, isNull);
        expect(first.infoMessage, 'Friend request sent to Alice.');
        expect(duplicate.infoMessage, 'Friend request already sent to Alice.');
        expect(service.friendRequests, hasLength(1));
        expect(service.friendRequests.single.targetIp, '192.168.1.10');
        expect(router.hasPendingFriendRequestForDevice(device), isTrue);
      },
    );

    test(
      'queues incoming request, normalizes MAC, and responds with acceptance',
      () async {
        final service = _RecordingLanDiscoveryService();
        final remembered = <_RememberedPeer>[];
        final trusted = <String>[];
        final router = _buildRouter(
          lanDiscoveryService: service,
          rememberVisibleFriendPeer: remembered.add,
          setFriendStatus: ({required macAddress, required isFriend}) async {
            if (isFriend) {
              trusted.add(macAddress);
            }
          },
        );

        final incoming = router.handleFriendRequest(
          FriendRequestEvent(
            requestId: 'incoming-1',
            requesterIp: '192.168.1.20',
            requesterName: 'Bob',
            requesterMacAddress: '11-22-33-44-55-66',
            observedAt: DateTime(2026, 1, 1, 10),
          ),
        );
        final accepted = await router.respondToFriendRequest(
          requestId: 'incoming-1',
          accept: true,
        );

        expect(incoming.infoMessage, 'New friend request from Bob.');
        expect(router.incomingFriendRequests, isEmpty);
        expect(accepted.infoMessage, 'Bob added to friends.');
        expect(remembered.last.macAddress, '11:22:33:44:55:66');
        expect(trusted.single, '11:22:33:44:55:66');
        expect(service.friendResponses.single.accepted, isTrue);
      },
    );

    test(
      'accepted outgoing response trusts responder and falls back to pending name',
      () async {
        final service = _RecordingLanDiscoveryService();
        final remembered = <_RememberedPeer>[];
        final trusted = <String>[];
        final router = _buildRouter(
          lanDiscoveryService: service,
          rememberVisibleFriendPeer: remembered.add,
          setFriendStatus: ({required macAddress, required isFriend}) async {
            if (isFriend) {
              trusted.add(macAddress);
            }
          },
        );
        await router.sendFriendRequest(
          DiscoveredDevice(
            ip: '192.168.1.30',
            macAddress: '22-33-44-55-66-77',
            deviceName: 'Carol',
            isAppDetected: true,
            lastSeen: DateTime(2026),
          ),
        );

        final result = await router.acceptFriendResponse(
          FriendResponseEvent(
            requestId: service.friendRequests.single.requestId,
            responderIp: '192.168.1.30',
            responderName: ' ',
            responderMacAddress: '22-33-44-55-66-77',
            accepted: true,
            observedAt: DateTime(2026, 1, 1, 11),
          ),
        );

        expect(result.infoMessage, 'Carol accepted your friend request.');
        expect(remembered.single.deviceName, 'Carol');
        expect(trusted.single, '22:33:44:55:66:77');
      },
    );
  });
}

DiscoveryFriendRequestRouter _buildRouter({
  required _RecordingLanDiscoveryService lanDiscoveryService,
  bool Function(String? macAddress)? isTrustedMac,
  void Function(_RememberedPeer peer)? rememberVisibleFriendPeer,
  Future<void> Function({required String macAddress, required bool isFriend})?
  setFriendStatus,
}) {
  return DiscoveryFriendRequestRouter(
    lanDiscoveryService: lanDiscoveryService,
    fileHashService: FileHashService(),
    localNameProvider: () => 'Local',
    localDeviceMacProvider: () => '02:00:00:00:00:01',
    isTrustedMac: isTrustedMac ?? (_) => false,
    deviceByIp: (_) => null,
    rememberVisibleFriendPeer:
        ({
          required ip,
          required macAddress,
          required deviceName,
          required observedAt,
          peerId,
        }) async {
          rememberVisibleFriendPeer?.call(
            _RememberedPeer(
              ip: ip,
              macAddress: macAddress,
              deviceName: deviceName,
              observedAt: observedAt,
              peerId: peerId,
            ),
          );
        },
    setFriendStatus:
        setFriendStatus ?? ({required macAddress, required isFriend}) async {},
    showFriendRequestNotification: (_) async {},
    log: (_) {},
    nowProvider: () => DateTime(2026, 1, 1),
  );
}

class _RecordingLanDiscoveryService extends LanDiscoveryService {
  final List<_FriendRequestCall> friendRequests = <_FriendRequestCall>[];
  final List<_FriendResponseCall> friendResponses = <_FriendResponseCall>[];

  @override
  Future<void> sendFriendRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
  }) async {
    friendRequests.add(
      _FriendRequestCall(
        targetIp: targetIp,
        requestId: requestId,
        requesterName: requesterName,
        requesterMacAddress: requesterMacAddress,
      ),
    );
  }

  @override
  Future<void> sendFriendResponse({
    required String targetIp,
    required String requestId,
    required String responderName,
    required String responderMacAddress,
    required bool accepted,
  }) async {
    friendResponses.add(
      _FriendResponseCall(
        targetIp: targetIp,
        requestId: requestId,
        responderName: responderName,
        responderMacAddress: responderMacAddress,
        accepted: accepted,
      ),
    );
  }
}

class _FriendRequestCall {
  const _FriendRequestCall({
    required this.targetIp,
    required this.requestId,
    required this.requesterName,
    required this.requesterMacAddress,
  });

  final String targetIp;
  final String requestId;
  final String requesterName;
  final String requesterMacAddress;
}

class _FriendResponseCall {
  const _FriendResponseCall({
    required this.targetIp,
    required this.requestId,
    required this.responderName,
    required this.responderMacAddress,
    required this.accepted,
  });

  final String targetIp;
  final String requestId;
  final String responderName;
  final String responderMacAddress;
  final bool accepted;
}

class _RememberedPeer {
  const _RememberedPeer({
    required this.ip,
    required this.macAddress,
    required this.deviceName,
    required this.observedAt,
    this.peerId,
  });

  final String ip;
  final String macAddress;
  final String deviceName;
  final DateTime observedAt;
  final String? peerId;
}

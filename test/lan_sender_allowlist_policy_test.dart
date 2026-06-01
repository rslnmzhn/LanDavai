import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_common.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/data/lan_sender_allowlist_policy.dart';

void main() {
  group('LanSenderAllowlistPolicy', () {
    late LanSenderAllowlistPolicy policy;

    setUp(() {
      policy = LanSenderAllowlistPolicy();
    });

    test('rejects unusable sender IPs', () {
      expect(policy.isUsablePacketSenderIp('0.0.0.0'), isFalse);
      expect(policy.isUsablePacketSenderIp('127.0.0.1'), isFalse);
      expect(policy.isUsablePacketSenderIp('255.255.255.255'), isFalse);
      expect(policy.isUsablePacketSenderIp('192.168.1.20'), isTrue);
    });

    test(
      'allows same subnet, configured target, and internet peer senders',
      () {
        final packet = _transferRequestPacket();

        expect(
          policy.isAllowedSenderForPacket(
            packet: packet,
            senderIp: '192.168.1.25',
            localIps: <String>{'192.168.1.10'},
            configuredTargetIps: const <String>{},
            internetPeerIpAllowlist: const <String>{},
          ),
          isTrue,
        );
        expect(
          policy.isAllowedSenderForPacket(
            packet: packet,
            senderIp: '203.0.113.7',
            localIps: <String>{'192.168.1.10'},
            configuredTargetIps: <String>{'203.0.113.7'},
            internetPeerIpAllowlist: const <String>{},
          ),
          isTrue,
        );
        expect(
          policy.isAllowedSenderForPacket(
            packet: packet,
            senderIp: '198.51.100.9',
            localIps: <String>{'192.168.1.10'},
            configuredTargetIps: const <String>{},
            internetPeerIpAllowlist: <String>{'198.51.100.9'},
          ),
          isTrue,
        );
      },
    );

    test(
      'allows non-local discover request but rejects other foreign packets',
      () {
        final logs = <String>[];

        expect(
          policy.isAllowedSenderForPacket(
            packet: _presencePacket(prefix: lanDiscoverPrefix),
            senderIp: '203.0.113.8',
            localIps: <String>{'192.168.1.10'},
            configuredTargetIps: const <String>{},
            internetPeerIpAllowlist: const <String>{},
            log: logs.add,
          ),
          isTrue,
        );
        expect(logs.single, contains('Allowing discover request'));

        expect(
          policy.isAllowedSenderForPacket(
            packet: _transferRequestPacket(),
            senderIp: '203.0.113.8',
            localIps: <String>{'192.168.1.10'},
            configuredTargetIps: const <String>{},
            internetPeerIpAllowlist: const <String>{},
          ),
          isFalse,
        );
      },
    );

    test('presence sender allowance expires after TTL', () {
      final observedAt = DateTime(2026);
      policy.markPresenceAllowedSender('203.0.113.8', observedAt);

      expect(
        policy.isAllowedSenderForPacket(
          packet: _transferRequestPacket(),
          senderIp: '203.0.113.8',
          localIps: <String>{'192.168.1.10'},
          configuredTargetIps: const <String>{},
          internetPeerIpAllowlist: const <String>{},
          now: observedAt.add(const Duration(seconds: 19)),
        ),
        isTrue,
      );

      expect(
        policy.isAllowedSenderForPacket(
          packet: _transferRequestPacket(),
          senderIp: '203.0.113.8',
          localIps: <String>{'192.168.1.10'},
          configuredTargetIps: const <String>{},
          internetPeerIpAllowlist: const <String>{},
          now: observedAt.add(const Duration(seconds: 21)),
        ),
        isFalse,
      );
    });
  });
}

LanDiscoveryPresencePacket _presencePacket({required String prefix}) {
  return LanDiscoveryPresencePacket(
    instanceId: 'remote-instance',
    prefix: prefix,
    deviceName: 'Remote',
    peerId: 'peer',
  );
}

LanTransferRequestPacket _transferRequestPacket() {
  return LanTransferRequestPacket(
    instanceId: 'remote-instance',
    requestId: 'request-1',
    senderName: 'Remote',
    senderMacAddress: 'AA-BB-CC-DD-EE-FF',
    sharedCacheId: 'cache-1',
    sharedLabel: 'Cache',
    items: const <TransferAnnouncementItem>[],
  );
}

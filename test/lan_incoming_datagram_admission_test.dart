import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/lan_incoming_datagram_admission.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_sender_allowlist_policy.dart';

void main() {
  late LanPacketCodec codec;
  late LanSenderAllowlistPolicy allowlistPolicy;
  late List<String> logs;
  late LanIncomingDatagramAdmission admission;

  setUp(() {
    codec = LanPacketCodec();
    allowlistPolicy = LanSenderAllowlistPolicy();
    logs = <String>[];
    admission = LanIncomingDatagramAdmission(
      packetCodec: codec,
      senderAllowlistPolicy: allowlistPolicy,
      log: logs.add,
    );
  });

  test('rejects unusable sender IPs before decoding', () {
    final accepted = admission.admit(
      bytes: utf8.encode('not-a-packet'),
      senderIp: '0.0.0.0',
      localIps: const <String>{'192.168.1.10'},
      localInstanceId: 'local-instance',
      configuredTargetIps: const <String>{},
      internetPeerIpAllowlist: const <String>{},
    );

    expect(accepted, isNull);
    expect(logs.single, contains('Ignoring packet from invalid sender IP'));
  });

  test('suppresses local self packets and matching local instance packets', () {
    final localSenderAccepted = admission.admit(
      bytes: utf8.encode(
        codec.encodeDiscoveryResponse(
          instanceId: 'remote-instance',
          deviceName: 'Remote',
          localPeerId: 'remote-peer',
        ),
      ),
      senderIp: '192.168.1.10',
      localIps: const <String>{'192.168.1.10'},
      localInstanceId: 'local-instance',
      configuredTargetIps: const <String>{},
      internetPeerIpAllowlist: const <String>{},
    );
    final localInstanceAccepted = admission.admit(
      bytes: utf8.encode(
        codec.encodeDiscoveryResponse(
          instanceId: 'local-instance',
          deviceName: 'Local echo',
          localPeerId: 'local-peer',
        ),
      ),
      senderIp: '192.168.1.20',
      localIps: const <String>{'192.168.1.10'},
      localInstanceId: 'local-instance',
      configuredTargetIps: const <String>{},
      internetPeerIpAllowlist: const <String>{},
    );

    expect(localSenderAccepted, isNull);
    expect(localInstanceAccepted, isNull);
  });

  test('rejects non-presence packets from foreign subnets', () {
    final packet = codec.encodeTransferRequest(
      instanceId: 'remote-instance',
      requestId: 'request-1',
      senderName: 'Remote',
      senderMacAddress: 'aa:bb:cc:dd:ee:ff',
      sharedCacheId: 'cache-1',
      sharedLabel: 'Docs',
      items: <TransferAnnouncementItem>[
        TransferAnnouncementItem(
          fileName: 'file.txt',
          sizeBytes: 1,
          sha256: 'hash',
        ),
      ],
      createdAtMs: 1,
    );

    final accepted = admission.admit(
      bytes: packet!.bytes,
      senderIp: '100.64.0.8',
      localIps: const <String>{'192.168.1.10'},
      localInstanceId: 'local-instance',
      configuredTargetIps: const <String>{},
      internetPeerIpAllowlist: const <String>{},
    );

    expect(accepted, isNull);
    expect(logs.single, contains('Ignoring packet from foreign subnet'));
  });

  test('accepts configured target packets and produces context', () {
    final observedAt = DateTime.utc(2024, 1, 1);
    final message = codec.encodeDiscoveryResponse(
      instanceId: 'remote-instance',
      deviceName: 'Remote',
      localPeerId: 'remote-peer',
    );

    final accepted = admission.admit(
      bytes: utf8.encode(message),
      senderIp: '100.64.0.8',
      localIps: const <String>{'192.168.1.10'},
      localInstanceId: 'local-instance',
      configuredTargetIps: const <String>{'100.64.0.8'},
      internetPeerIpAllowlist: const <String>{},
      observedAt: observedAt,
    );

    expect(accepted, isNotNull);
    expect(accepted!.senderIp, '100.64.0.8');
    expect(accepted.observedAt, observedAt);
    expect(accepted.packet, isA<LanDiscoveryPresencePacket>());
  });

  test('allows discover requests from foreign senders for handshake', () {
    final message = codec.encodeDiscoveryRequest(
      instanceId: 'remote-instance',
      deviceName: 'Remote',
      localPeerId: 'remote-peer',
    );

    final accepted = admission.admit(
      bytes: utf8.encode(message),
      senderIp: '100.64.0.8',
      localIps: const <String>{'192.168.1.10'},
      localInstanceId: 'local-instance',
      configuredTargetIps: const <String>{},
      internetPeerIpAllowlist: const <String>{},
    );

    expect(accepted, isNotNull);
    expect(
      logs.single,
      contains('Allowing discover request from non-local sender'),
    );
  });
}

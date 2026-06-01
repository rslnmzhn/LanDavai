import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/lan_discovery_target_registry.dart';
import 'package:landa/features/discovery/data/lan_internet_peer_endpoint.dart';
import 'package:landa/features/discovery/data/lan_sender_allowlist_policy.dart';

void main() {
  late LanSenderAllowlistPolicy allowlistPolicy;
  late LanDiscoveryTargetRegistry registry;

  setUp(() {
    allowlistPolicy = LanSenderAllowlistPolicy();
    registry = LanDiscoveryTargetRegistry(
      isUsableTargetIp: allowlistPolicy.isUsablePacketSenderIp,
      discoveryPort: 40404,
    );
  });

  test('normalizes internet peer endpoints and allow-list IP snapshots', () {
    registry.updateInternetPeers(const <InternetPeerEndpoint>[
      InternetPeerEndpoint(
        friendId: ' friend-1 ',
        host: ' 100.64.0.8 ',
        port: 0,
      ),
      InternetPeerEndpoint(
        friendId: 'friend-2',
        host: '100.64.0.9',
        port: 45000,
      ),
      InternetPeerEndpoint(friendId: '', host: '100.64.0.10', port: 40404),
      InternetPeerEndpoint(
        friendId: 'friend-3',
        host: 'example.test',
        port: 40404,
      ),
    ]);

    expect(registry.internetPeers, hasLength(2));
    expect(registry.internetPeers.first.friendId, 'friend-1');
    expect(registry.internetPeers.first.host, '100.64.0.8');
    expect(registry.internetPeers.first.port, 40404);
    expect(registry.internetPeers.last.port, 45000);
    expect(registry.internetPeerIpAllowlist, <String>{
      '100.64.0.8',
      '100.64.0.9',
    });
  });

  test(
    'normalizes configured target IPs through injected usability policy',
    () {
      registry.updateConfiguredTargetIps(const <String>{
        ' 100.64.0.8 ',
        '255.255.255.255',
        '224.0.0.1',
        'not-an-ip',
        '127.0.0.1',
      });

      expect(registry.configuredTargetIps, <String>{'100.64.0.8'});
    },
  );

  test('clears only configured target snapshot', () {
    registry.updateInternetPeers(const <InternetPeerEndpoint>[
      InternetPeerEndpoint(
        friendId: 'friend-1',
        host: '100.64.0.8',
        port: 40404,
      ),
    ]);
    registry.updateConfiguredTargetIps(const <String>{'100.64.0.9'});

    registry.clearConfiguredTargetIps();

    expect(registry.configuredTargetIps, isEmpty);
    expect(registry.internetPeers, hasLength(1));
    expect(registry.internetPeerIpAllowlist, <String>{'100.64.0.8'});
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/discovery_internet_friend_command_adapter.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';

import 'test_support/test_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiscoveryInternetFriendCommandAdapter', () {
    test('parses IPv4 endpoints and defaults the discovery port', () {
      expect(
        DiscoveryInternetFriendCommandAdapter.parseEndpoint('203.0.113.7'),
        ('203.0.113.7', LanDiscoveryService.discoveryPort),
      );
      expect(
        DiscoveryInternetFriendCommandAdapter.parseEndpoint(
          '203.0.113.7:50505',
        ),
        ('203.0.113.7', 50505),
      );
      expect(
        DiscoveryInternetFriendCommandAdapter.parseEndpoint('999.0.0.1'),
        isNull,
      );
      expect(
        DiscoveryInternetFriendCommandAdapter.parseEndpoint('203.0.113.7:0'),
        isNull,
      );
      expect(
        DiscoveryInternetFriendCommandAdapter.parseEndpoint(
          '203.0.113.7:70000',
        ),
        isNull,
      );
    });

    test(
      'saves friend endpoint and syncs only enabled internet peers',
      () async {
        final harness = await TestAppDatabaseHarness.create(
          prefix: 'landa_internet_friend_adapter_',
        );
        addTearDown(harness.dispose);
        final repository = FriendRepository(database: harness.database);
        final store = InternetPeerEndpointStore(friendRepository: repository);
        final lanDiscoveryService = _RecordingLanDiscoveryService();
        final adapter = DiscoveryInternetFriendCommandAdapter(
          internetPeerEndpointStore: store,
          lanDiscoveryService: lanDiscoveryService,
        );

        final result = await adapter.saveFriend(
          friendId: ' friend-1 ',
          displayName: ' Alice ',
          endpoint: '203.0.113.7:50505',
        );

        expect(result.isSuccess, isTrue);
        expect(result.infoMessage, 'Friend saved: friend-1');
        final firstPeers = await repository.listFriends();
        expect(firstPeers.single.friendId, 'friend-1');
        expect(firstPeers.single.displayName, 'Alice');
        expect(lanDiscoveryService.internetPeers, hasLength(1));
        expect(lanDiscoveryService.internetPeers.single.friendId, 'friend-1');
        expect(lanDiscoveryService.internetPeers.single.host, '203.0.113.7');
        expect(lanDiscoveryService.internetPeers.single.port, 50505);

        await adapter.saveFriend(
          friendId: 'friend-2',
          displayName: 'Bob',
          endpoint: '198.51.100.8:40404',
          isEnabled: false,
        );

        expect(await repository.listFriends(), hasLength(2));
        expect(lanDiscoveryService.internetPeers, hasLength(1));
        expect(lanDiscoveryService.internetPeers.single.friendId, 'friend-1');
      },
    );

    test('returns validation failure before mutating repository', () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_internet_friend_adapter_validation_',
      );
      addTearDown(harness.dispose);
      final repository = FriendRepository(database: harness.database);
      final adapter = DiscoveryInternetFriendCommandAdapter(
        internetPeerEndpointStore: InternetPeerEndpointStore(
          friendRepository: repository,
        ),
        lanDiscoveryService: _RecordingLanDiscoveryService(),
      );

      final missingId = await adapter.saveFriend(
        friendId: ' ',
        displayName: 'Alice',
        endpoint: '203.0.113.7',
      );
      final badEndpoint = await adapter.saveFriend(
        friendId: 'friend-1',
        displayName: 'Alice',
        endpoint: 'not-an-ip',
      );

      expect(missingId.errorMessage, 'Friend ID is required.');
      expect(badEndpoint.errorMessage, contains('Endpoint must be'));
      expect(await repository.listFriends(), isEmpty);
    });
  });
}

class _RecordingLanDiscoveryService extends LanDiscoveryService {
  List<InternetPeerEndpoint> internetPeers = const <InternetPeerEndpoint>[];

  @override
  void updateInternetPeers(List<InternetPeerEndpoint> peers) {
    internetPeers = List<InternetPeerEndpoint>.of(peers);
  }
}

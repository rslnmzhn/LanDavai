import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late FriendRepository repository;
  late InternetPeerEndpointStore store;
  late Database database;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_internet_peer_endpoint_store_',
    );
    repository = FriendRepository(database: harness.database);
    store = InternetPeerEndpointStore(friendRepository: repository);
    database = await harness.database.database;
  });

  tearDown(() async {
    store.dispose();
    await harness.dispose();
  });

  test(
    'endpoint rows round-trip through the store with current friends semantics',
    () async {
      await store.saveEndpoint(
        friendId: 'peer-1',
        displayName: 'Remote peer',
        endpointHost: '203.0.113.7',
        endpointPort: 40404,
        isEnabled: true,
      );

      expect(store.peers, hasLength(1));
      expect(store.peers.single.friendId, 'peer-1');
      expect(store.peers.single.displayName, 'Remote peer');
      expect(store.peers.single.endpointHost, '203.0.113.7');
      expect(store.peers.single.endpointPort, 40404);
      expect(store.peers.single.isEnabled, isTrue);
    },
  );

  test(
    'enable and disable semantics stay unchanged under the store boundary',
    () async {
      await store.saveEndpoint(
        friendId: 'peer-1',
        displayName: 'Remote peer',
        endpointHost: '203.0.113.7',
        endpointPort: 40404,
        isEnabled: true,
      );

      await store.setEndpointEnabled(friendId: 'peer-1', isEnabled: false);

      expect(store.peers, hasLength(1));
      expect(store.peers.single.isEnabled, isFalse);
    },
  );

  test('remove works unchanged through the store boundary', () async {
    await store.saveEndpoint(
      friendId: 'peer-1',
      displayName: 'Remote peer',
      endpointHost: '203.0.113.7',
      endpointPort: 40404,
      isEnabled: true,
    );

    await store.removeEndpoint('peer-1');

    expect(store.peers, isEmpty);
  });

  test('endpoint mutation does not write known_devices trust state', () async {
    await store.saveEndpoint(
      friendId: 'peer-1',
      displayName: 'Remote peer',
      endpointHost: '203.0.113.7',
      endpointPort: 40404,
      isEnabled: true,
    );
    await store.setEndpointEnabled(friendId: 'peer-1', isEnabled: false);
    await store.removeEndpoint('peer-1');

    final deviceRows = await database.query(AppDatabase.knownDevicesTable);
    expect(deviceRows, isEmpty);
  });
}

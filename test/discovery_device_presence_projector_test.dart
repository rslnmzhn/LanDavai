import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_device_presence_projector.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/discovery/domain/friend_peer.dart';

import 'test_support/test_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiscoveryDevicePresenceProjector', () {
    test('normalizes OS and resolves device category', () {
      expect(
        DiscoveryDevicePresenceProjector.normalizeOperatingSystemName(
          'Android 15',
        ),
        'Android',
      );
      expect(
        DiscoveryDevicePresenceProjector.normalizeOperatingSystemName('iPadOS'),
        'iOS',
      );
      expect(
        DiscoveryDevicePresenceProjector.resolveDeviceCategory(
          deviceType: 'tablet',
          operatingSystem: null,
        ),
        DeviceCategory.phone,
      );
      expect(
        DiscoveryDevicePresenceProjector.resolveDeviceCategory(
          deviceType: null,
          operatingSystem: 'Windows',
        ),
        DeviceCategory.pc,
      );
    });

    test(
      'projects app presence with friend display name and nearby metadata',
      () async {
        final harness = await TestAppDatabaseHarness.create(
          prefix: 'landa_presence_projector_app_',
        );
        addTearDown(harness.dispose);

        final registry = DeviceRegistry(
          deviceAliasRepository: DeviceAliasRepository(
            database: harness.database,
          ),
        );
        await registry.recordPeerIdentity(
          macAddress: 'aa:bb:cc:dd:ee:ff',
          peerId: 'peer-alice',
          ip: '192.168.1.20',
        );
        final projector = DiscoveryDevicePresenceProjector(
          deviceRegistry: registry,
        );

        final observedAt = DateTime(2026, 1, 1, 12);
        final result = projector.projectAppPresence(
          event: AppPresenceEvent(
            ip: '192.168.1.20',
            deviceName: 'Raw Alice',
            peerId: ' peer-alice ',
            operatingSystem: 'windows 11',
            deviceType: 'desktop',
            nearbyTransferPort: 45321,
            observedAt: observedAt,
          ),
          existing: DiscoveredDevice(
            ip: '192.168.1.20',
            lastSeen: DateTime(2025),
            macAddress: 'aa-bb-cc-dd-ee-ff',
          ),
          friends: const <FriendPeer>[
            FriendPeer(
              friendId: 'peer-alice',
              displayName: 'Alice Friend',
              endpointHost: 'example.test',
              endpointPort: 47777,
              isEnabled: true,
              updatedAtMs: 1,
            ),
          ],
        );

        expect(result.normalizedPeerId, 'peer-alice');
        expect(result.normalizedMacAddress, 'aa:bb:cc:dd:ee:ff');
        expect(result.device.deviceName, 'Alice Friend');
        expect(result.device.operatingSystem, 'Windows');
        expect(result.device.deviceCategory, DeviceCategory.pc);
        expect(result.device.isNearbyTransferAvailable, isTrue);
        expect(result.device.nearbyTransferPort, 45321);
        expect(result.device.nearbyAvailabilityObservedAt, observedAt);
        expect(result.device.isAppDetected, isTrue);
        expect(result.device.isReachable, isTrue);
      },
    );

    test(
      'projects visible friend peers and preserves existing name on blank input',
      () async {
        final harness = await TestAppDatabaseHarness.create(
          prefix: 'landa_presence_projector_friend_',
        );
        addTearDown(harness.dispose);

        final projector = DiscoveryDevicePresenceProjector(
          deviceRegistry: DeviceRegistry(
            deviceAliasRepository: DeviceAliasRepository(
              database: harness.database,
            ),
          ),
        );
        final existing = DiscoveredDevice(
          ip: '192.168.1.30',
          lastSeen: DateTime(2025),
          deviceName: 'Existing Name',
          peerId: 'existing-peer',
        );

        final projected = projector.projectVisibleFriendPeer(
          ip: ' 192.168.1.30 ',
          macAddress: 'AA-BB-CC-DD-EE-11',
          deviceName: '   ',
          observedAt: DateTime(2026),
          existing: existing,
        );

        expect(projected, isNotNull);
        expect(projected!.macAddress, 'aa:bb:cc:dd:ee:11');
        expect(projected.deviceName, 'Existing Name');
        expect(projected.peerId, 'existing-peer');
        expect(projected.isAppDetected, isTrue);
        expect(projected.isReachable, isTrue);
      },
    );
  });
}

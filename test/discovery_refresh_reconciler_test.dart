import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_device_presence_projector.dart';
import 'package:landa/features/discovery/application/discovery_refresh_reconciler.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';

import 'test_support/test_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiscoveryRefreshReconciler', () {
    test(
      'records normalized host MACs and marks scanned hosts reachable',
      () async {
        final harness = await TestAppDatabaseHarness.create(
          prefix: 'landa_refresh_reconciler_seen_',
        );
        addTearDown(harness.dispose);
        final reconciler = _buildReconciler(harness.database);

        final result = reconciler.reconcile(
          currentDevicesByIp: const <String, DiscoveredDevice>{},
          hosts: const <String, String?>{
            '192.168.1.10': 'AA-BB-CC-DD-EE-FF',
            '192.168.1.11': null,
          },
          observedAt: DateTime(2026, 1, 1, 10),
          selectedDeviceIp: '192.168.1.10',
        );

        expect(result.seenMacToIp, {'aa:bb:cc:dd:ee:ff': '192.168.1.10'});
        expect(result.devicesByIp['192.168.1.10']?.isReachable, isTrue);
        expect(
          result.devicesByIp['192.168.1.10']?.macAddress,
          'aa:bb:cc:dd:ee:ff',
        );
        expect(result.devicesByIp['192.168.1.11']?.macAddress, isNull);
        expect(result.hasSelectedDevice, isTrue);
      },
    );

    test(
      'removes stale non-app hosts and keeps stale app devices unreachable',
      () async {
        final harness = await TestAppDatabaseHarness.create(
          prefix: 'landa_refresh_reconciler_stale_',
        );
        addTearDown(harness.dispose);
        final reconciler = _buildReconciler(harness.database);
        final staleAppDevice = DiscoveredDevice(
          ip: '192.168.1.20',
          deviceName: 'Alice',
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 9),
        );
        final staleHost = DiscoveredDevice(
          ip: '192.168.1.21',
          isAppDetected: false,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 9),
        );

        final result = reconciler.reconcile(
          currentDevicesByIp: <String, DiscoveredDevice>{
            staleAppDevice.ip: staleAppDevice,
            staleHost.ip: staleHost,
          },
          hosts: const <String, String?>{},
          observedAt: DateTime(2026, 1, 1, 10),
          selectedDeviceIp: staleHost.ip,
        );

        expect(result.devicesByIp, isNot(contains(staleHost.ip)));
        expect(result.removedIps, contains(staleHost.ip));
        expect(result.devicesByIp[staleAppDevice.ip]?.isReachable, isFalse);
        expect(result.hasSelectedDevice, isFalse);
      },
    );

    test('resolves host MAC from registry when scan omits MAC', () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_refresh_reconciler_registry_',
      );
      addTearDown(harness.dispose);
      final registry = DeviceRegistry(
        deviceAliasRepository: DeviceAliasRepository(
          database: harness.database,
        ),
      );
      await registry.recordSeenDevices(const <String, String>{
        '11:22:33:44:55:66': '192.168.1.30',
      });
      final reconciler = DiscoveryRefreshReconciler(
        devicePresenceProjector: DiscoveryDevicePresenceProjector(
          deviceRegistry: registry,
        ),
      );

      final result = reconciler.reconcile(
        currentDevicesByIp: const <String, DiscoveredDevice>{},
        hosts: const <String, String?>{'192.168.1.30': null},
        observedAt: DateTime(2026, 1, 1, 10),
        selectedDeviceIp: null,
      );

      expect(
        result.devicesByIp['192.168.1.30']?.macAddress,
        '11:22:33:44:55:66',
      );
    });
  });
}

DiscoveryRefreshReconciler _buildReconciler(dynamic database) {
  return DiscoveryRefreshReconciler(
    devicePresenceProjector: DiscoveryDevicePresenceProjector(
      deviceRegistry: DeviceRegistry(
        deviceAliasRepository: DeviceAliasRepository(database: database),
      ),
    ),
  );
}

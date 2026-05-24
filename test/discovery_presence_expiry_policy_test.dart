import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/discovery_presence_expiry_policy.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';

void main() {
  group('DiscoveryPresenceExpiryPolicy', () {
    final now = DateTime(2026, 5, 25, 12);
    const policy = DiscoveryPresenceExpiryPolicy(
      appPresenceTtl: Duration(seconds: 12),
      nearbyAvailabilityTtl: Duration(seconds: 8),
    );

    test('expires stale nearby availability before app presence', () {
      final observedAt = now.subtract(const Duration(seconds: 9));
      final device = DiscoveredDevice(
        ip: '192.168.1.20',
        lastSeen: observedAt,
        isReachable: true,
        isAppDetected: true,
        appPresenceObservedAt: observedAt,
        isNearbyTransferAvailable: true,
        nearbyTransferPort: 45678,
        nearbyAvailabilityObservedAt: observedAt,
      );

      final result = policy.expire(now: now, device: device);

      expect(result.changed, isTrue);
      expect(result.shouldRemove, isFalse);
      expect(result.device.isAppDetected, isTrue);
      expect(result.device.isReachable, isTrue);
      expect(result.device.isNearbyTransferAvailable, isFalse);
      expect(result.device.nearbyTransferPort, isNull);
      expect(result.device.nearbyAvailabilityObservedAt, isNull);
    });

    test('removes app-only presence without fresher reachability signal', () {
      final observedAt = now.subtract(const Duration(seconds: 13));
      final device = DiscoveredDevice(
        ip: '192.168.1.21',
        lastSeen: observedAt,
        isReachable: true,
        isAppDetected: true,
        appPresenceObservedAt: observedAt,
      );

      final result = policy.expire(now: now, device: device);

      expect(result.changed, isTrue);
      expect(result.shouldRemove, isTrue);
      expect(result.device.isAppDetected, isFalse);
      expect(result.device.isReachable, isFalse);
      expect(result.device.appPresenceObservedAt, isNull);
    });

    test(
      'preserves reachability when host scan is fresher than app presence',
      () {
        final appObservedAt = now.subtract(const Duration(seconds: 13));
        final device = DiscoveredDevice(
          ip: '192.168.1.22',
          lastSeen: now.subtract(const Duration(seconds: 1)),
          isReachable: true,
          isAppDetected: true,
          appPresenceObservedAt: appObservedAt,
        );

        final result = policy.expire(now: now, device: device);

        expect(result.changed, isTrue);
        expect(result.shouldRemove, isFalse);
        expect(result.device.isAppDetected, isFalse);
        expect(result.device.isReachable, isTrue);
      },
    );
  });
}

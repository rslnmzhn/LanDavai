import '../data/network_host_scanner.dart';
import '../domain/discovered_device.dart';
import 'device_registry.dart';
import 'discovery_refresh_reconciler.dart';

class DiscoveryRefreshRunResult {
  const DiscoveryRefreshRunResult({
    required this.devicesByIp,
    required this.removedIps,
    required this.hasSelectedDevice,
    required this.hostCount,
  });

  final Map<String, DiscoveredDevice> devicesByIp;
  final List<String> removedIps;
  final bool hasSelectedDevice;
  final int hostCount;
}

class DiscoveryRefreshRunner {
  DiscoveryRefreshRunner({
    required NetworkHostScanner networkHostScanner,
    required DeviceRegistry deviceRegistry,
    required DiscoveryRefreshReconciler refreshReconciler,
  }) : _networkHostScanner = networkHostScanner,
       _deviceRegistry = deviceRegistry,
       _refreshReconciler = refreshReconciler;

  final NetworkHostScanner _networkHostScanner;
  final DeviceRegistry _deviceRegistry;
  final DiscoveryRefreshReconciler _refreshReconciler;

  Future<DiscoveryRefreshRunResult> run({
    required Map<String, DiscoveredDevice> currentDevicesByIp,
    required Set<String> localSourceIps,
    required Set<String> configuredTargetIps,
    required DateTime observedAt,
    required String? selectedDeviceIp,
    required bool Function() isDisposed,
  }) async {
    final hosts = await _networkHostScanner.scanActiveHosts(
      localSourceIps: localSourceIps,
      configuredTargetIps: configuredTargetIps,
    );
    if (isDisposed()) {
      return DiscoveryRefreshRunResult(
        devicesByIp: currentDevicesByIp,
        removedIps: const <String>[],
        hasSelectedDevice: selectedDeviceIp != null,
        hostCount: hosts.length,
      );
    }

    final reconcileResult = _refreshReconciler.reconcile(
      currentDevicesByIp: currentDevicesByIp,
      hosts: hosts,
      observedAt: observedAt,
      selectedDeviceIp: selectedDeviceIp,
    );

    if (reconcileResult.seenMacToIp.isNotEmpty) {
      await _deviceRegistry.recordSeenDevices(reconcileResult.seenMacToIp);
    }

    return DiscoveryRefreshRunResult(
      devicesByIp: reconcileResult.devicesByIp,
      removedIps: reconcileResult.removedIps,
      hasSelectedDevice: reconcileResult.hasSelectedDevice,
      hostCount: hosts.length,
    );
  }
}

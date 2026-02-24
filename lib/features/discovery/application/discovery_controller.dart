import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/lan_discovery_service.dart';
import '../data/network_host_scanner.dart';
import '../domain/discovered_device.dart';

enum DiscoveryFlowState { idle, discovering }

class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required LanDiscoveryService lanDiscoveryService,
    required NetworkHostScanner networkHostScanner,
  }) : _lanDiscoveryService = lanDiscoveryService,
       _networkHostScanner = networkHostScanner;

  final LanDiscoveryService _lanDiscoveryService;
  final NetworkHostScanner _networkHostScanner;

  final Map<String, DiscoveredDevice> _devicesByIp =
      <String, DiscoveredDevice>{};
  Timer? _scanTimer;
  bool _started = false;

  DiscoveryFlowState _state = DiscoveryFlowState.idle;
  String? _localIp;
  final String _localName = Platform.localHostname;
  String? _errorMessage;

  DiscoveryFlowState get state => _state;
  String? get localIp => _localIp;
  String get localName => _localName;
  String? get errorMessage => _errorMessage;

  List<DiscoveredDevice> get devices {
    final values = _devicesByIp.values.toList(growable: false);
    values.sort((a, b) {
      if (a.isAppDetected != b.isAppDetected) {
        return a.isAppDetected ? -1 : 1;
      }
      return _compareIp(a.ip, b.ip);
    });
    return values;
  }

  int get appDetectedCount =>
      _devicesByIp.values.where((d) => d.isAppDetected).length;

  Future<void> start() async {
    if (_started) {
      return;
    }

    _started = true;
    _state = DiscoveryFlowState.discovering;
    notifyListeners();

    await _resolveLocalAddress();

    try {
      await _lanDiscoveryService.start(
        deviceName: _localName,
        onAppDetected: _onAppDetected,
      );

      await refresh();
      _scanTimer = Timer.periodic(
        const Duration(seconds: 12),
        (_) => refresh(),
      );
    } catch (error) {
      _errorMessage = 'LAN discovery error: $error';
    } finally {
      _state = DiscoveryFlowState.idle;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _state = DiscoveryFlowState.discovering;
    notifyListeners();

    try {
      final hosts = await _networkHostScanner.scanActiveHosts();
      final now = DateTime.now();

      for (final ip in hosts) {
        _devicesByIp[ip] =
            (_devicesByIp[ip] ?? DiscoveredDevice(ip: ip, lastSeen: now))
                .copyWith(isReachable: true, lastSeen: now);
      }

      final staleIps = <String>[];
      _devicesByIp.forEach((ip, device) {
        if (hosts.contains(ip)) {
          return;
        }

        final age = now.difference(device.lastSeen);
        final stale = age > const Duration(minutes: 2);
        final keep = device.isAppDetected || !stale;
        if (!keep) {
          staleIps.add(ip);
          return;
        }

        _devicesByIp[ip] = device.copyWith(isReachable: false);
      });
      for (final staleIp in staleIps) {
        _devicesByIp.remove(staleIp);
      }

      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Host scan failed: $error';
    } finally {
      _state = DiscoveryFlowState.idle;
      notifyListeners();
    }
  }

  void _onAppDetected(AppPresenceEvent event) {
    final existing = _devicesByIp[event.ip];
    _devicesByIp[event.ip] =
        (existing ?? DiscoveredDevice(ip: event.ip, lastSeen: event.observedAt))
            .copyWith(
              deviceName: event.deviceName,
              isAppDetected: true,
              isReachable: true,
              lastSeen: event.observedAt,
            );
    notifyListeners();
  }

  Future<void> _resolveLocalAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    for (final interface in interfaces) {
      if (interface.addresses.isEmpty) {
        continue;
      }
      final address = interface.addresses.first.address;
      _localIp = address;
      notifyListeners();
      return;
    }
  }

  int _compareIp(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList(growable: false);
    final bParts = b.split('.').map(int.parse).toList(growable: false);
    for (var i = 0; i < 4; i += 1) {
      final cmp = aParts[i].compareTo(bParts[i]);
      if (cmp != 0) {
        return cmp;
      }
    }
    return 0;
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _lanDiscoveryService.stop();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:developer' as developer;
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

  static const Duration _autoRefreshInterval = Duration(seconds: 30);

  final LanDiscoveryService _lanDiscoveryService;
  final NetworkHostScanner _networkHostScanner;

  final Map<String, DiscoveredDevice> _devicesByIp =
      <String, DiscoveredDevice>{};
  Timer? _scanTimer;
  bool _started = false;
  bool _isRefreshInProgress = false;
  bool _isManualRefreshInProgress = false;

  DiscoveryFlowState _state = DiscoveryFlowState.idle;
  String? _localIp;
  final String _localName = Platform.localHostname;
  String? _errorMessage;

  DiscoveryFlowState get state => _state;
  bool get isManualRefreshInProgress => _isManualRefreshInProgress;
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
      _log('start() ignored: controller already started');
      return;
    }

    _started = true;

    await _resolveLocalAddress();

    try {
      _log('Starting discovery. localName=$_localName localIp=$_localIp');
      await _lanDiscoveryService.start(
        deviceName: _localName,
        onAppDetected: _onAppDetected,
        preferredSourceIp: _localIp,
      );

      await _refresh(isManual: false);
      _scanTimer = Timer.periodic(
        _autoRefreshInterval,
        (_) => unawaited(_refresh(isManual: false)),
      );
    } catch (error) {
      _errorMessage = 'LAN discovery error: $error';
      _log(_errorMessage!);
    }
  }

  Future<void> refresh() => _refresh(isManual: true);

  Future<void> _refresh({required bool isManual}) async {
    if (_isRefreshInProgress) {
      _log('Refresh skipped. Another refresh is already running.');
      return;
    }

    _isRefreshInProgress = true;
    if (isManual) {
      _isManualRefreshInProgress = true;
      _state = DiscoveryFlowState.discovering;
      notifyListeners();
    }

    try {
      _log('${isManual ? "Manual" : "Auto"} refresh scan started');
      final hosts = await _networkHostScanner.scanActiveHosts(
        preferredSourceIp: _localIp,
      );
      final now = DateTime.now();
      _log(
        '${isManual ? "Manual" : "Auto"} refresh scan finished. hosts=${hosts.length}',
      );

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

        if (!device.isAppDetected) {
          staleIps.add(ip);
          return;
        }

        _devicesByIp[ip] = device.copyWith(isReachable: false);
      });
      for (final staleIp in staleIps) {
        _devicesByIp.remove(staleIp);
      }
      _log(
        'Device list updated. total=${_devicesByIp.length} '
        'appDetected=$appDetectedCount removed=${staleIps.length}',
      );

      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Host scan failed: $error';
      _log(_errorMessage!);
    } finally {
      _isRefreshInProgress = false;
      if (isManual) {
        _isManualRefreshInProgress = false;
        _state = DiscoveryFlowState.idle;
      }
      notifyListeners();
    }
  }

  void _onAppDetected(AppPresenceEvent event) {
    _log('App handshake detected from ${event.ip} (${event.deviceName})');
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

    InternetAddress? bestAddress;
    String? bestInterfaceName;
    var bestScore = -100000;

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final score = _scoreAddress(interface.name, address.address);
        _log(
          'Interface candidate: ${interface.name} -> ${address.address} '
          '(score=$score)',
        );
        if (score > bestScore) {
          bestScore = score;
          bestAddress = address;
          bestInterfaceName = interface.name;
        }
      }
    }

    if (bestAddress != null) {
      _localIp = bestAddress.address;
      _log(
        'Selected local interface: $bestInterfaceName '
        '(${bestAddress.address})',
      );
      notifyListeners();
      return;
    }

    _log('No suitable IPv4 local interface found');
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

  void _log(String message) {
    developer.log(message, name: 'DiscoveryController');
  }

  int _scoreAddress(String interfaceName, String ip) {
    final lower = interfaceName.toLowerCase();
    var score = 0;

    if (_isLikelyVirtualInterface(lower)) {
      score -= 400;
    } else {
      score += 100;
    }

    if (_isInSubnet(ip, 192, 168)) {
      score += 220;
    } else if (_isInSubnet(ip, 10, null)) {
      score += 170;
    } else if (_isInRange172Private(ip)) {
      score += 120;
    } else if (_isInSubnet(ip, 100, null)) {
      score += 60;
    } else {
      score += 20;
    }

    if (lower.contains('wi-fi') ||
        lower.contains('wifi') ||
        lower.contains('wlan') ||
        lower.contains('ethernet') ||
        lower.contains('eth')) {
      score += 50;
    }

    return score;
  }

  bool _isLikelyVirtualInterface(String lowerName) {
    const hints = <String>[
      'loopback',
      'docker',
      'vmware',
      'virtual',
      'vethernet',
      'hyper-v',
      'vbox',
      'wsl',
      'tailscale',
      'zerotier',
      'hamachi',
      'tun',
      'tap',
      'bridge',
    ];
    return hints.any(lowerName.contains);
  }

  bool _isInSubnet(String ip, int first, int? second) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final firstOctet = int.tryParse(parts[0]);
    final secondOctet = int.tryParse(parts[1]);
    if (firstOctet == null || secondOctet == null) {
      return false;
    }
    if (firstOctet != first) {
      return false;
    }
    if (second != null && secondOctet != second) {
      return false;
    }
    return true;
  }

  bool _isInRange172Private(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == null || second == null) {
      return false;
    }
    return first == 172 && second >= 16 && second <= 31;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

class AppPresenceEvent {
  AppPresenceEvent({
    required this.ip,
    required this.deviceName,
    required this.observedAt,
  });

  final String ip;
  final String deviceName;
  final DateTime observedAt;
}

class LanDiscoveryService {
  static const int discoveryPort = 40404;
  static const String _discoverPrefix = 'LANDA_DISCOVER_V1';
  static const String _responsePrefix = 'LANDA_HERE_V1';
  static const MethodChannel _androidNetworkChannel = MethodChannel(
    'landa/network',
  );

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Set<String> _localIps = <String>{};
  bool _started = false;
  String? _preferredSourceIp;
  final String _instanceId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
  static const List<String> _virtualInterfaceHints = <String>[
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

  Future<void> start({
    required String deviceName,
    required void Function(AppPresenceEvent event) onAppDetected,
    String? preferredSourceIp,
  }) async {
    if (_started) {
      _log('start() ignored: service already running');
      return;
    }
    _started = true;

    _preferredSourceIp = preferredSourceIp;
    _localIps = await _loadLocalIps(preferredSourceIp: preferredSourceIp);
    _log('Starting UDP discovery on $discoveryPort. localIps=$_localIps');
    await _acquireAndroidMulticastLock();

    // anyIPv4 is more reliable for receiving broadcast discovery packets
    // on Android devices; subnet filtering is applied in code.
    final bindAddress = InternetAddress.anyIPv4;
    _socket = await RawDatagramSocket.bind(
      bindAddress,
      discoveryPort,
      reuseAddress: true,
      reusePort: false,
    );
    _socket?.broadcastEnabled = true;

    _socket?.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }

      Datagram? datagram = _socket?.receive();
      while (datagram != null) {
        final senderIp = datagram.address.address;
        if (_localIps.contains(senderIp)) {
          datagram = _socket?.receive();
          continue;
        }
        if (_preferredSourceIp != null &&
            !_isSame24Subnet(senderIp, _preferredSourceIp!)) {
          _log('Ignoring packet from foreign subnet: $senderIp');
          datagram = _socket?.receive();
          continue;
        }

        final message = utf8.decode(datagram.data, allowMalformed: true);
        final packet = _parsePacket(message);
        if (packet == null) {
          datagram = _socket?.receive();
          continue;
        }
        if (packet.instanceId == _instanceId) {
          datagram = _socket?.receive();
          continue;
        }

        if (packet.prefix == _discoverPrefix) {
          _log('Discover request from $senderIp');
          final response = '$_responsePrefix|$_instanceId|$deviceName';
          _socket?.send(utf8.encode(response), datagram.address, discoveryPort);
          _log('Discover response sent to $senderIp');
        } else if (packet.prefix == _responsePrefix) {
          final remoteName = packet.deviceName;
          _log('Discover response received from $senderIp ($remoteName)');
          onAppDetected(
            AppPresenceEvent(
              ip: senderIp,
              deviceName: remoteName,
              observedAt: DateTime.now(),
            ),
          );
        }
        datagram = _socket?.receive();
      }
    });

    await _sendDiscoveryPing(deviceName);
    _beaconTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _sendDiscoveryPing(deviceName),
    );
  }

  Future<void> stop() async {
    _log('Stopping UDP discovery');
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _socket?.close();
    _socket = null;
    _started = false;
    await _releaseAndroidMulticastLock();
  }

  Future<void> _sendDiscoveryPing(String deviceName) async {
    final request = '$_discoverPrefix|$_instanceId|$deviceName';
    final bytes = utf8.encode(request);

    _log('Broadcasting discover packet');
    _socket?.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);
    for (final localIp in _localIps) {
      final broadcast = _toBroadcastAddress(localIp);
      if (broadcast != null) {
        _socket?.send(bytes, broadcast, discoveryPort);
        _log('Discover packet sent to ${broadcast.address}');
      }
    }
  }

  _DiscoveryPacket? _parsePacket(String message) {
    final parts = message.split('|');
    if (parts.isEmpty) {
      return null;
    }

    final prefix = parts[0].trim();
    if (prefix != _discoverPrefix && prefix != _responsePrefix) {
      return null;
    }

    // Backward compatibility with old payload format: PREFIX|deviceName
    if (parts.length == 2) {
      final legacyName = parts[1].trim();
      return _DiscoveryPacket(
        prefix: prefix,
        instanceId: 'legacy',
        deviceName: legacyName.isEmpty ? 'Unknown device' : legacyName,
      );
    }

    if (parts.length >= 3) {
      final instanceId = parts[1].trim();
      final deviceName = parts.sublist(2).join('|').trim();
      return _DiscoveryPacket(
        prefix: prefix,
        instanceId: instanceId,
        deviceName: deviceName.isEmpty ? 'Unknown device' : deviceName,
      );
    }

    return null;
  }

  InternetAddress? _toBroadcastAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return null;
    }
    return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
  }

  Future<Set<String>> _loadLocalIps({String? preferredSourceIp}) async {
    if (preferredSourceIp != null && _isValidIpv4(preferredSourceIp)) {
      _log('Using preferred source IP for UDP discovery: $preferredSourceIp');
      return <String>{preferredSourceIp};
    }

    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final ips = <String>{};
    final fallbackIps = <String>{};
    for (final interface in interfaces) {
      final lowerName = interface.name.toLowerCase();
      final isVirtual = _virtualInterfaceHints.any(lowerName.contains);
      for (final address in interface.addresses) {
        if (isVirtual) {
          fallbackIps.add(address.address);
          continue;
        }
        ips.add(address.address);
      }
    }
    return ips.isNotEmpty ? ips : fallbackIps;
  }

  bool _isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        return false;
      }
    }
    return true;
  }

  bool _isSame24Subnet(String ip, String baseIp) {
    if (!_isValidIpv4(ip) || !_isValidIpv4(baseIp)) {
      return false;
    }
    final a = ip.split('.');
    final b = baseIp.split('.');
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
  }

  void _log(String message) {
    developer.log(message, name: 'LanDiscoveryService');
  }

  Future<void> _acquireAndroidMulticastLock() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidNetworkChannel.invokeMethod<void>('acquireMulticastLock');
      _log('Android multicast lock acquired');
    } catch (error) {
      _log('Failed to acquire Android multicast lock: $error');
    }
  }

  Future<void> _releaseAndroidMulticastLock() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidNetworkChannel.invokeMethod<void>('releaseMulticastLock');
      _log('Android multicast lock released');
    } catch (error) {
      _log('Failed to release Android multicast lock: $error');
    }
  }
}

class _DiscoveryPacket {
  const _DiscoveryPacket({
    required this.prefix,
    required this.instanceId,
    required this.deviceName,
  });

  final String prefix;
  final String instanceId;
  final String deviceName;
}

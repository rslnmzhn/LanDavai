import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

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
  static const String _discoverPrefix = 'IP_TRANSFERER_DISCOVER_V1';
  static const String _responsePrefix = 'IP_TRANSFERER_HERE_V1';

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Set<String> _localIps = <String>{};
  bool _started = false;
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

    _localIps = await _loadLocalIps(preferredSourceIp: preferredSourceIp);
    _log('Starting UDP discovery on $discoveryPort. localIps=$_localIps');
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
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

        final message = utf8.decode(datagram.data, allowMalformed: true);
        if (message.startsWith(_discoverPrefix)) {
          _log('Discover request from $senderIp');
          final response = '$_responsePrefix|$deviceName';
          _socket?.send(utf8.encode(response), datagram.address, discoveryPort);
          _log('Discover response sent to $senderIp');
        } else if (message.startsWith(_responsePrefix)) {
          final remoteName = _parseDeviceName(message);
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
  }

  Future<void> _sendDiscoveryPing(String deviceName) async {
    final request = '$_discoverPrefix|$deviceName';
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

  String _parseDeviceName(String message) {
    final parts = message.split('|');
    if (parts.length < 2 || parts[1].trim().isEmpty) {
      return 'Unknown device';
    }
    return parts[1].trim();
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

  void _log(String message) {
    developer.log(message, name: 'LanDiscoveryService');
  }
}

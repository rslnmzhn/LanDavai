import 'dart:async';
import 'dart:convert';
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

  Future<void> start({
    required String deviceName,
    required void Function(AppPresenceEvent event) onAppDetected,
  }) async {
    if (_started) {
      return;
    }
    _started = true;

    _localIps = await _loadLocalIps();
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
          final response = '$_responsePrefix|$deviceName';
          _socket?.send(utf8.encode(response), datagram.address, discoveryPort);
        } else if (message.startsWith(_responsePrefix)) {
          final remoteName = _parseDeviceName(message);
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
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _socket?.close();
    _socket = null;
    _started = false;
  }

  Future<void> _sendDiscoveryPing(String deviceName) async {
    final request = '$_discoverPrefix|$deviceName';
    final bytes = utf8.encode(request);

    _socket?.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);
    for (final localIp in _localIps) {
      final broadcast = _toBroadcastAddress(localIp);
      if (broadcast != null) {
        _socket?.send(bytes, broadcast, discoveryPort);
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

  Future<Set<String>> _loadLocalIps() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final ips = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        ips.add(address.address);
      }
    }
    return ips;
  }
}

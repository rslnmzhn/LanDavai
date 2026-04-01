import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

abstract class DiscoveryTransportAdapter {
  Set<String> get localIps;
  bool get isStarted;
  int? get boundPort;

  Future<void> start({
    required int port,
    required void Function(Datagram datagram) onDatagram,
    required Set<String> localSourceIps,
  });

  Future<void> stop();

  void send({
    required List<int> bytes,
    required InternetAddress address,
    required int port,
    required String context,
  });
}

class UdpDiscoveryTransportAdapter implements DiscoveryTransportAdapter {
  static const MethodChannel _androidNetworkChannel = MethodChannel(
    'landa/network',
  );

  RawDatagramSocket? _socket;
  Set<String> _localIps = <String>{};
  bool _started = false;

  @override
  Set<String> get localIps => Set<String>.unmodifiable(_localIps);

  @override
  bool get isStarted => _started;

  @override
  int? get boundPort => _socket?.port;

  @override
  Future<void> start({
    required int port,
    required void Function(Datagram datagram) onDatagram,
    required Set<String> localSourceIps,
  }) async {
    if (_started) {
      _log('start() ignored: transport already running');
      return;
    }

    _started = true;
    _localIps = localSourceIps.where(_isValidIpv4).toSet();
    _log('Starting UDP transport on $port. localIps=$_localIps');
    await _acquireAndroidMulticastLock();

    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: false,
      );
      socket.broadcastEnabled = true;
      _socket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }

        Datagram? datagram = socket.receive();
        while (datagram != null) {
          onDatagram(datagram);
          datagram = socket.receive();
        }
      });
    } catch (_) {
      _started = false;
      _socket = null;
      _localIps = <String>{};
      await _releaseAndroidMulticastLock();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_started && _socket == null) {
      return;
    }

    _log('Stopping UDP transport');
    _socket?.close();
    _socket = null;
    _localIps = <String>{};
    _started = false;
    await _releaseAndroidMulticastLock();
  }

  @override
  void send({
    required List<int> bytes,
    required InternetAddress address,
    required int port,
    required String context,
  }) {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    if (bytes.isEmpty) {
      return;
    }
    if (address.type != InternetAddressType.IPv4) {
      _log('Skipping UDP send ($context): non-IPv4 target ${address.address}.');
      return;
    }
    if (address.address == '0.0.0.0') {
      _log('Skipping UDP send ($context): invalid target 0.0.0.0.');
      return;
    }
    try {
      socket.send(bytes, address, port);
    } on SocketException catch (error) {
      _log('UDP send failed ($context) -> ${address.address}:$port: $error');
    } catch (error) {
      _log('UDP send failed ($context) -> ${address.address}:$port: $error');
    }
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

  void _log(String message) {
    developer.log(message, name: 'UdpDiscoveryTransportAdapter');
  }
}

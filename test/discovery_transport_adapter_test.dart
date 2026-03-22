import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/discovery_transport_adapter.dart';

void main() {
  test('owns UDP lifecycle and keeps start stop idempotent', () async {
    final adapter = UdpDiscoveryTransportAdapter();

    await adapter.start(port: 0, onDatagram: (_) {});

    expect(adapter.isStarted, isTrue);
    expect(adapter.boundPort, isNotNull);
    final initialPort = adapter.boundPort;

    await adapter.start(port: 0, onDatagram: (_) {});

    expect(adapter.isStarted, isTrue);
    expect(adapter.boundPort, initialPort);

    await adapter.stop();

    expect(adapter.isStarted, isFalse);
    expect(adapter.boundPort, isNull);

    await adapter.stop();

    expect(adapter.isStarted, isFalse);
  });

  test('preserves low level UDP send and receive behavior', () async {
    final adapter = UdpDiscoveryTransportAdapter();
    final inboundDatagram = Completer<Datagram>();
    RawDatagramSocket? senderSocket;
    RawDatagramSocket? receiverSocket;

    try {
      await adapter.start(
        port: 0,
        preferredSourceIp: '127.0.0.1',
        onDatagram: (datagram) {
          if (!inboundDatagram.isCompleted) {
            inboundDatagram.complete(datagram);
          }
        },
      );

      final adapterPort = adapter.boundPort;
      expect(adapterPort, isNotNull);

      senderSocket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      senderSocket.send(
        'adapter-inbound'.codeUnits,
        InternetAddress.loopbackIPv4,
        adapterPort!,
      );

      final receivedByAdapter = await inboundDatagram.future.timeout(
        const Duration(seconds: 3),
      );
      expect(String.fromCharCodes(receivedByAdapter.data), 'adapter-inbound');

      final outboundDatagram = Completer<Datagram>();
      receiverSocket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      receiverSocket.listen((event) {
        if (event != RawSocketEvent.read || outboundDatagram.isCompleted) {
          return;
        }
        final datagram = receiverSocket?.receive();
        if (datagram != null) {
          outboundDatagram.complete(datagram);
        }
      });

      adapter.send(
        bytes: 'adapter-outbound'.codeUnits,
        address: InternetAddress.loopbackIPv4,
        port: receiverSocket.port,
        context: 'adapter-test',
      );

      final receivedFromAdapter = await outboundDatagram.future.timeout(
        const Duration(seconds: 3),
      );
      expect(
        String.fromCharCodes(receivedFromAdapter.data),
        'adapter-outbound',
      );
    } finally {
      senderSocket?.close();
      receiverSocket?.close();
      await adapter.stop();
    }
  });
}

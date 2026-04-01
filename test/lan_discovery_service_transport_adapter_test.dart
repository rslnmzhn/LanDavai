import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/discovery_transport_adapter.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';

void main() {
  late LanPacketCodec codec;
  late FakeDiscoveryTransportAdapter transportAdapter;
  late LanDiscoveryService service;

  setUp(() {
    codec = LanPacketCodec();
    transportAdapter = FakeDiscoveryTransportAdapter(
      localIps: <String>{'192.168.1.10'},
    );
    service = LanDiscoveryService(transportAdapter: transportAdapter);
  });

  test('delegates transport lifecycle ownership to adapter', () async {
    await service.start(
      deviceName: 'Local workstation',
      localPeerId: 'local-peer',
      onAppDetected: (_) {},
    );

    expect(transportAdapter.startCalls, 1);
    expect(
      transportAdapter.sentPackets.map((packet) => packet.context),
      contains('discover-broadcast'),
    );

    await service.start(
      deviceName: 'Local workstation',
      localPeerId: 'local-peer',
      onAppDetected: (_) {},
    );

    expect(transportAdapter.startCalls, 1);

    await service.stop();

    expect(transportAdapter.stopCalls, 1);
  });

  test(
    'keeps discovery response routing unchanged after transport extraction',
    () async {
      AppPresenceEvent? detectedEvent;

      await service.start(
        deviceName: 'Local workstation',
        localPeerId: 'local-peer',
        onAppDetected: (event) {
          detectedEvent = event;
        },
      );

      final requestMessage = codec.encodeDiscoveryResponse(
        instanceId: 'remote-instance',
        deviceName: 'Remote node',
        localPeerId: 'local-peer',
      );

      transportAdapter.emitDatagram(
        bytes: utf8.encode(requestMessage),
        senderIp: '192.168.1.24',
        senderPort: LanDiscoveryService.discoveryPort,
      );

      expect(detectedEvent, isNotNull);
      expect(detectedEvent!.ip, '192.168.1.24');
      expect(detectedEvent!.deviceName, 'Remote node');
      expect(detectedEvent!.peerId, 'local-peer');
    },
  );

  test(
    'keeps encoded packet send path routed through transport adapter',
    () async {
      await service.start(
        deviceName: 'Local workstation',
        localPeerId: 'local-peer',
        onAppDetected: (_) {},
      );
      transportAdapter.clearSentPackets();

      await service.sendTransferRequest(
        targetIp: '192.168.1.20',
        requestId: 'request-1',
        senderName: 'Alice',
        senderMacAddress: 'aa:bb:cc:dd:ee:ff',
        sharedCacheId: 'cache-1',
        sharedLabel: 'Docs',
        items: <TransferAnnouncementItem>[
          TransferAnnouncementItem(
            fileName: 'report.pdf',
            sizeBytes: 42,
            sha256: 'hash-1',
          ),
        ],
      );

      expect(transportAdapter.sentPackets, hasLength(1));
      final packet = transportAdapter.sentPackets.single;
      final decoded = LanPacketCodec.decodeEnvelopeForTest(
        message: utf8.decode(packet.bytes),
        expectedPrefix: LanPacketCodec.transferRequestPrefix,
      );

      expect(packet.context, 'LANDA_TRANSFER_REQUEST_V1');
      expect(packet.address.address, '192.168.1.20');
      expect(packet.port, LanDiscoveryService.discoveryPort);
      expect(decoded?['requestId'], 'request-1');
      expect(decoded?['senderName'], 'Alice');
      expect(decoded?['sharedCacheId'], 'cache-1');
    },
  );
}

class FakeDiscoveryTransportAdapter implements DiscoveryTransportAdapter {
  FakeDiscoveryTransportAdapter({required Set<String> localIps})
    : _localIps = Set<String>.from(localIps);

  final Set<String> _localIps;
  final List<RecordedTransportPacket> sentPackets = <RecordedTransportPacket>[];
  int startCalls = 0;
  int stopCalls = 0;
  bool _started = false;
  void Function(Datagram datagram)? _onDatagram;

  @override
  Set<String> get localIps => Set<String>.unmodifiable(_localIps);

  @override
  bool get isStarted => _started;

  @override
  int? get boundPort => LanDiscoveryService.discoveryPort;

  @override
  Future<void> start({
    required int port,
    required void Function(Datagram datagram) onDatagram,
    String? preferredSourceIp,
  }) async {
    if (_started) {
      return;
    }
    startCalls += 1;
    _started = true;
    _onDatagram = onDatagram;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    _started = false;
    _onDatagram = null;
  }

  @override
  void send({
    required List<int> bytes,
    required InternetAddress address,
    required int port,
    required String context,
  }) {
    sentPackets.add(
      RecordedTransportPacket(
        bytes: Uint8List.fromList(bytes),
        address: address,
        port: port,
        context: context,
      ),
    );
  }

  void emitDatagram({
    required List<int> bytes,
    required String senderIp,
    required int senderPort,
  }) {
    final callback = _onDatagram;
    if (callback == null) {
      throw StateError('Transport callback is not registered.');
    }
    callback(
      Datagram(
        Uint8List.fromList(bytes),
        InternetAddress(senderIp),
        senderPort,
      ),
    );
  }

  void clearSentPackets() {
    sentPackets.clear();
  }
}

class RecordedTransportPacket {
  const RecordedTransportPacket({
    required this.bytes,
    required this.address,
    required this.port,
    required this.context,
  });

  final Uint8List bytes;
  final InternetAddress address;
  final int port;
  final String context;
}

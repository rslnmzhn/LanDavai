import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/discovery_transport_adapter.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';

void main() {
  late FakePacketCodec codec;
  late FakeTransportAdapter transportAdapter;
  late LanDiscoveryService service;

  setUp(() {
    codec = FakePacketCodec();
    transportAdapter = FakeTransportAdapter(localIps: <String>{'192.168.1.10'});
    service = LanDiscoveryService(
      transportAdapter: transportAdapter,
      packetCodec: codec,
    );
  });

  tearDown(() async {
    await service.stop();
  });

  test('delegates incoming packet decode to codec boundary', () async {
    AppPresenceEvent? detectedEvent;

    await service.start(
      deviceName: 'Local workstation',
      localPeerId: 'local-peer',
      onAppDetected: (event) {
        detectedEvent = event;
      },
    );

    transportAdapter.emitDatagram(
      bytes: utf8.encode('ignored-by-fake-codec'),
      senderIp: '192.168.1.24',
      senderPort: LanDiscoveryService.discoveryPort,
    );

    expect(codec.decodeIncomingCalls, 1);
    expect(detectedEvent, isNotNull);
    expect(detectedEvent!.deviceName, 'Codec peer');
    expect(detectedEvent!.peerId, 'codec-peer-id');
  });

  test(
    'delegates outgoing transfer packet encoding to codec boundary',
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

      expect(codec.encodeTransferRequestCalls, 1);
      expect(transportAdapter.sentPackets, hasLength(1));
      expect(
        utf8.decode(transportAdapter.sentPackets.single.bytes),
        'codec-transfer-packet',
      );
    },
  );
}

class FakePacketCodec extends LanPacketCodec {
  int decodeIncomingCalls = 0;
  int encodeTransferRequestCalls = 0;

  @override
  LanInboundPacket? decodeIncomingPacket(String message) {
    decodeIncomingCalls += 1;
    return const LanDiscoveryPresencePacket(
      prefix: LanPacketCodec.responsePrefix,
      instanceId: 'remote-instance',
      deviceName: 'Codec peer',
      peerId: 'codec-peer-id',
    );
  }

  @override
  EncodedLanPacket? encodeTransferRequest({
    required String instanceId,
    required String requestId,
    required String senderName,
    required String senderMacAddress,
    required String sharedCacheId,
    required String sharedLabel,
    required List<TransferAnnouncementItem> items,
    required int createdAtMs,
  }) {
    encodeTransferRequestCalls += 1;
    return EncodedLanPacket(
      prefix: LanPacketCodec.transferRequestPrefix,
      bytes: Uint8List.fromList(utf8.encode('codec-transfer-packet')),
    );
  }
}

class FakeTransportAdapter implements DiscoveryTransportAdapter {
  FakeTransportAdapter({required Set<String> localIps})
    : _localIps = Set<String>.from(localIps);

  final Set<String> _localIps;
  final List<RecordedTransportPacket> sentPackets = <RecordedTransportPacket>[];
  void Function(Datagram datagram)? _onDatagram;
  bool _started = false;

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
    _started = true;
    _onDatagram = onDatagram;
  }

  @override
  Future<void> stop() async {
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

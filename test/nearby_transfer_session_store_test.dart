import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_availability_store.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/data/qr_payload_codec.dart';

import 'test_support/fake_nearby_transfer.dart';
import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  test(
    'lan fallback QR payload is sufficient for receiver connect without old discovery state',
    () async {
      final senderLanAdapter = FakeNearbyTransferTransportAdapter(
        hostingPort: 47890,
      );
      final receiverLanAdapter = FakeNearbyTransferTransportAdapter();
      final senderStore = buildTestNearbyTransferStore(
        readModel: harness.readModel,
        lanAdapter: senderLanAdapter,
        localDeviceId: 'sender-device',
        localDeviceName: 'Sender',
        localIp: '192.168.0.44',
      );
      final receiverStore = buildTestNearbyTransferStore(
        readModel: harness.readModel,
        lanAdapter: receiverLanAdapter,
        localDeviceId: 'receiver-device',
        localDeviceName: 'Receiver',
        localIp: '192.168.0.55',
      );
      addTearDown(senderStore.dispose);
      addTearDown(receiverStore.dispose);

      await senderStore.prepareSendFlow();
      await receiverStore.prepareReceiveFlow();

      final qrPayload = senderStore.qrPayloadText;
      expect(qrPayload, isNotNull);
      final decoded = const NearbyTransferQrCodec().decode(qrPayload!);

      await receiverStore.handleQrPayloadText(qrPayload);

      expect(decoded, isNotNull);
      expect(receiverLanAdapter.connectCalls, 1);
      expect(receiverLanAdapter.lastConnectHost, '192.168.0.44');
      expect(receiverLanAdapter.lastConnectPort, 47890);
      expect(receiverLanAdapter.lastExpectedSessionId, decoded!.sessionId);
    },
  );

  test(
    'candidate devices refresh on bounded cadence when visible LAN projection changes',
    () async {
      harness.controller.setTestDevices(<DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.0.2',
          macAddress: 'aa:bb:cc:00:00:02',
          deviceName: 'Peer A',
          isNearbyTransferAvailable: true,
          nearbyTransferPort: 45321,
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 10),
        ),
      ]);
      final store = buildTestNearbyTransferStore(
        readModel: harness.readModel,
        candidateRefreshInterval: const Duration(milliseconds: 25),
      );
      addTearDown(store.dispose);

      await store.prepareReceiveFlow();

      expect(store.candidateDevices, hasLength(1));
      expect(store.candidateDevices.single.displayName, 'Peer A');

      harness.controller.setTestDevices(<DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.0.3',
          macAddress: 'aa:bb:cc:00:00:03',
          deviceName: 'Peer B',
          isNearbyTransferAvailable: true,
          nearbyTransferPort: 45322,
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 11),
        ),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(store.candidateDevices, hasLength(1));
      expect(store.candidateDevices.single.displayName, 'Peer B');
      expect(store.candidateDevices.single.host, '192.168.0.3');
      expect(store.candidateDevices.single.port, 45322);
    },
  );

  test(
    'candidate devices exclude general app peers until nearby availability is advertised',
    () async {
      harness.controller.setTestDevices(<DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.0.4',
          macAddress: 'aa:bb:cc:00:00:04',
          deviceName: 'Peer C',
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 12),
        ),
      ]);
      final store = buildTestNearbyTransferStore(readModel: harness.readModel);
      addTearDown(store.dispose);

      await store.prepareReceiveFlow();

      expect(store.candidateDevices, isEmpty);

      harness.controller.setTestDevices(<DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.0.4',
          macAddress: 'aa:bb:cc:00:00:04',
          deviceName: 'Peer C',
          isNearbyTransferAvailable: true,
          nearbyTransferPort: 45323,
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 12, 1),
        ),
      ]);
      await store.refreshCandidates();

      expect(store.candidateDevices, hasLength(1));
      expect(store.candidateDevices.single.displayName, 'Peer C');
      expect(store.candidateDevices.single.port, 45323);
    },
  );

  test('disconnect without restart clears active connection state', () async {
    final lanAdapter = FakeNearbyTransferTransportAdapter();
    final store = buildTestNearbyTransferStore(
      readModel: harness.readModel,
      lanAdapter: lanAdapter,
    );
    addTearDown(store.dispose);

    await store.prepareReceiveFlow();
    lanAdapter.emit(
      const NearbyTransferConnectedEvent(
        peer: NearbyTransferPeerDevice(
          deviceId: 'peer-1',
          displayName: 'Peer',
          host: '192.168.0.10',
        ),
        sessionId: 'session-1',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(store.peer?.deviceId, 'peer-1');
    expect(store.hasActiveConnection, isTrue);

    await store.disconnect(restart: false);

    expect(store.peer, isNull);
    expect(store.hasActiveConnection, isFalse);
    expect(store.selectedCandidateId, isNull);
  });

  test(
    'send flow advertises nearby availability only while the sheet session is active',
    () async {
      final availabilityStore = NearbyTransferAvailabilityStore();
      final lanAdapter = FakeNearbyTransferTransportAdapter(hostingPort: 47890);
      final store = buildTestNearbyTransferStore(
        readModel: harness.readModel,
        lanAdapter: lanAdapter,
        availabilityStore: availabilityStore,
      );
      addTearDown(store.dispose);

      expect(availabilityStore.isLanFallbackAdvertised, isFalse);

      await store.prepareSendFlow();

      expect(availabilityStore.lanFallbackPort, 47890);
      expect(availabilityStore.isLanFallbackAdvertised, isTrue);

      await store.disconnect(restart: false);

      expect(availabilityStore.lanFallbackPort, isNull);
      expect(availabilityStore.isLanFallbackAdvertised, isFalse);
    },
  );
}

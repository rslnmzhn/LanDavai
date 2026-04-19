import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_availability_store.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_handshake_service.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_session_store.dart';
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
    'duplicate taps on the same candidate are ignored while connection is in progress',
    () async {
      harness.controller.setTestDevices(<DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.0.20',
          macAddress: 'aa:bb:cc:00:00:20',
          deviceName: 'Peer A',
          isNearbyTransferAvailable: true,
          nearbyTransferPort: 45321,
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 10),
        ),
      ]);
      final lanAdapter = FakeNearbyTransferTransportAdapter();
      final store = buildTestNearbyTransferStore(
        readModel: harness.readModel,
        lanAdapter: lanAdapter,
      );
      addTearDown(store.dispose);

      await store.prepareReceiveFlow();
      final candidate = store.candidateDevices.single;

      await store.connectToCandidate(candidate);
      await store.connectToCandidate(candidate);

      expect(lanAdapter.connectCalls, 1);
      expect(store.selectedCandidateId, candidate.id);
      expect(store.phase, NearbyTransferSessionPhase.connecting);
    },
  );

  test(
    'qr-based receive connection auto-accepts handshake without manual code choice',
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
      await receiverStore.handleQrPayloadText(senderStore.qrPayloadText!);

      receiverLanAdapter.emit(
        const NearbyTransferConnectedEvent(
          peer: NearbyTransferPeerDevice(
            deviceId: 'sender-device',
            displayName: 'Sender',
            host: '192.168.0.44',
          ),
          sessionId: 'session-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      receiverLanAdapter.emit(
        const NearbyTransferHandshakeOfferEvent(
          verificationCode: <String>['1', '2'],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(receiverLanAdapter.sendHandshakeAcceptedCalls, 1);
      expect(receiverStore.phase, NearbyTransferSessionPhase.connected);
      expect(receiverStore.bannerMessage, 'Соединение подтверждено.');
    },
  );

  test('valid 2-digit handshake input confirms the session', () async {
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
    lanAdapter.emit(
      const NearbyTransferHandshakeOfferEvent(
        verificationCode: <String>['4', '2'],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await store.submitHandshakeCode('42');

    expect(lanAdapter.sendHandshakeAcceptedCalls, 1);
    expect(store.phase, NearbyTransferSessionPhase.connected);
    expect(store.bannerMessage, 'Соединение подтверждено.');
  });

  test(
    'invalid 2-digit handshake input does not confirm the session',
    () async {
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
      lanAdapter.emit(
        const NearbyTransferHandshakeOfferEvent(
          verificationCode: <String>['4', '2'],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await store.submitHandshakeCode('00');

      expect(lanAdapter.sendHandshakeAcceptedCalls, 0);
      expect(store.phase, NearbyTransferSessionPhase.awaitingHandshake);
      expect(store.bannerMessage, 'Код не совпал. Попробуйте ещё раз.');
    },
  );

  test('expired handshake code invalidates the session', () async {
    var now = DateTime(2026, 1, 1, 10, 0, 0);
    final lanAdapter = FakeNearbyTransferTransportAdapter();
    final store = buildTestNearbyTransferStore(
      readModel: harness.readModel,
      lanAdapter: lanAdapter,
      handshakeService: NearbyTransferHandshakeService(
        now: () => now,
        codeLifetime: const Duration(seconds: 1),
      ),
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
    lanAdapter.emit(
      const NearbyTransferHandshakeOfferEvent(
        verificationCode: <String>['4', '2'],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    now = now.add(const Duration(seconds: 2));
    await store.submitHandshakeCode('42');

    expect(store.phase, NearbyTransferSessionPhase.idle);
    expect(store.hasActiveConnection, isFalse);
    expect(
      store.bannerMessage,
      'Код подтверждения истёк. Подключитесь заново.',
    );
  });

  test(
    'repeated invalid entries trigger a cooldown before more attempts',
    () async {
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final lanAdapter = FakeNearbyTransferTransportAdapter();
      final store = buildTestNearbyTransferStore(
        readModel: harness.readModel,
        lanAdapter: lanAdapter,
        handshakeService: NearbyTransferHandshakeService(
          now: () => now,
          maxAttemptsBeforeCooldown: 2,
          cooldownDuration: const Duration(seconds: 5),
        ),
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
      lanAdapter.emit(
        const NearbyTransferHandshakeOfferEvent(
          verificationCode: <String>['4', '2'],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await store.submitHandshakeCode('00');
      await store.submitHandshakeCode('11');

      expect(store.isHandshakeCoolingDown, isTrue);
      expect(
        store.bannerMessage,
        startsWith('Слишком много попыток. Подождите'),
      );

      await store.submitHandshakeCode('42');
      expect(lanAdapter.sendHandshakeAcceptedCalls, 0);

      now = now.add(const Duration(seconds: 6));
      await store.submitHandshakeCode('42');

      expect(lanAdapter.sendHandshakeAcceptedCalls, 1);
      expect(store.phase, NearbyTransferSessionPhase.connected);
    },
  );

  test(
    'remote disconnect closes sender session instead of returning to wait',
    () async {
      final lanAdapter = FakeNearbyTransferTransportAdapter();
      final store = buildTestNearbyTransferStore(
        readModel: harness.readModel,
        lanAdapter: lanAdapter,
      );
      addTearDown(store.dispose);

      await store.prepareSendFlow();
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

      expect(store.hasActiveConnection, isTrue);

      lanAdapter.emit(
        const NearbyTransferDisconnectedEvent(message: 'Соединение закрыто.'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(store.hasActiveConnection, isFalse);
      expect(store.peer, isNull);
      expect(store.phase, NearbyTransferSessionPhase.idle);
      expect(store.bannerMessage, 'Соединение закрыто.');
    },
  );

  test(
    'incoming nearby offer stays in listing state until receiver explicitly downloads selected files',
    () async {
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
      lanAdapter.emit(
        const NearbyTransferIncomingSelectionOfferedEvent(
          requestId: 'offer-1',
          label: 'Фото и заметки',
          roots: <NearbyTransferRemoteOfferNode>[
            NearbyTransferRemoteOfferNode(
              id: 'image-1',
              name: 'photo.png',
              relativePath: 'photo.png',
              kind: NearbyTransferRemoteOfferNodeKind.file,
              sizeBytes: 2048,
              previewKind: NearbyTransferRemotePreviewKind.image,
            ),
            NearbyTransferRemoteOfferNode(
              id: 'text-1',
              name: 'notes.txt',
              relativePath: 'notes.txt',
              kind: NearbyTransferRemoteOfferNodeKind.file,
              sizeBytes: 128,
              previewKind: NearbyTransferRemotePreviewKind.text,
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(store.hasIncomingOffer, isTrue);
      expect(store.incomingFiles, hasLength(2));
      expect(lanAdapter.requestIncomingSelectionDownloadCalls, 0);

      store.toggleIncomingFileSelection('image-1', false);
      await store.downloadSelectedIncomingFiles();

      expect(lanAdapter.requestIncomingSelectionDownloadCalls, 1);
      expect(lanAdapter.lastDownloadRequestId, 'offer-1');
      expect(lanAdapter.lastDownloadFileIds, <String>['text-1']);
    },
  );

  test(
    'incoming structured folder offer preserves navigation and subtree exclusion',
    () async {
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
      lanAdapter.emit(
        const NearbyTransferIncomingSelectionOfferedEvent(
          requestId: 'offer-1',
          label: 'Trip',
          roots: <NearbyTransferRemoteOfferNode>[
            NearbyTransferRemoteOfferNode(
              id: 'dir:Trip',
              name: 'Trip',
              relativePath: 'Trip',
              kind: NearbyTransferRemoteOfferNodeKind.directory,
              sizeBytes: 2176,
              previewKind: NearbyTransferRemotePreviewKind.none,
              children: <NearbyTransferRemoteOfferNode>[
                NearbyTransferRemoteOfferNode(
                  id: 'image-1',
                  name: 'photo.png',
                  relativePath: 'Trip/photo.png',
                  kind: NearbyTransferRemoteOfferNodeKind.file,
                  sizeBytes: 2048,
                  previewKind: NearbyTransferRemotePreviewKind.image,
                ),
                NearbyTransferRemoteOfferNode(
                  id: 'dir:Trip/docs',
                  name: 'docs',
                  relativePath: 'Trip/docs',
                  kind: NearbyTransferRemoteOfferNodeKind.directory,
                  sizeBytes: 128,
                  previewKind: NearbyTransferRemotePreviewKind.none,
                  children: <NearbyTransferRemoteOfferNode>[
                    NearbyTransferRemoteOfferNode(
                      id: 'text-1',
                      name: 'notes.txt',
                      relativePath: 'Trip/docs/notes.txt',
                      kind: NearbyTransferRemoteOfferNodeKind.file,
                      sizeBytes: 128,
                      previewKind: NearbyTransferRemotePreviewKind.text,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(store.incomingRoots, hasLength(1));
      expect(store.visibleIncomingNodes.single.name, 'Trip');
      expect(store.canNavigateIncomingUp, isFalse);
      expect(store.isIncomingNodeSelected('dir:Trip'), isTrue);

      store.toggleIncomingNodeSelection('dir:Trip/docs', false);

      expect(store.isIncomingNodePartiallySelected('dir:Trip'), isTrue);
      expect(store.selectedIncomingFileIds, <String>{'image-1'});

      store.openIncomingDirectory('dir:Trip');
      expect(store.canNavigateIncomingUp, isTrue);
      expect(
        store.visibleIncomingNodes.map((node) => node.name).toList(),
        <String>['photo.png', 'docs'],
      );

      store.openIncomingDirectory('dir:Trip/docs');
      expect(
        store.visibleIncomingNodes.map((node) => node.name).toList(),
        <String>['notes.txt'],
      );

      await store.downloadSelectedIncomingFiles();

      expect(lanAdapter.requestIncomingSelectionDownloadCalls, 1);
      expect(lanAdapter.lastDownloadFileIds, <String>['image-1']);
    },
  );

  test(
    'incoming preview resolves through session store without starting download',
    () async {
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
      lanAdapter.emit(
        const NearbyTransferIncomingSelectionOfferedEvent(
          requestId: 'offer-1',
          label: 'Текст',
          roots: <NearbyTransferRemoteOfferNode>[
            NearbyTransferRemoteOfferNode(
              id: 'text-1',
              name: 'notes.txt',
              relativePath: 'notes.txt',
              kind: NearbyTransferRemoteOfferNodeKind.file,
              sizeBytes: 128,
              previewKind: NearbyTransferRemotePreviewKind.text,
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final previewFuture = store.loadIncomingPreview(
        store.incomingFiles.single,
      );
      await Future<void>.delayed(Duration.zero);
      expect(lanAdapter.requestIncomingSelectionPreviewCalls, 1);
      expect(lanAdapter.lastPreviewRequestId, 'offer-1');
      expect(lanAdapter.lastPreviewFileId, 'text-1');
      expect(lanAdapter.requestIncomingSelectionDownloadCalls, 0);

      lanAdapter.emit(
        const NearbyTransferRemotePreviewReadyEvent(
          preview: NearbyTransferRemoteFilePreview.text(
            requestId: 'offer-1',
            fileId: 'text-1',
            textContent: 'hello preview',
            isTruncated: false,
          ),
        ),
      );
      final preview = await previewFuture;

      expect(preview, isNotNull);
      expect(preview!.textContent, 'hello preview');
      expect(store.activeIncomingPreview?.textContent, 'hello preview');
      expect(lanAdapter.requestIncomingSelectionDownloadCalls, 0);
    },
  );

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

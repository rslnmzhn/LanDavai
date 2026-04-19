import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/data/lan_nearby_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_storage_service.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'host can send handshake offer immediately after connect without control-channel crash',
    () async {
      final sender = _buildAdapter();
      final receiver = _buildAdapter();
      addTearDown(() async {
        sender.dispose();
        receiver.dispose();
      });

      final sendCompleted = Completer<void>();
      final receivedOffer = Completer<List<String>>();
      Object? sendError;
      const verificationCode = <String>['1', '2'];

      final senderSubscription = sender.events.listen((event) {
        if (event is NearbyTransferConnectedEvent &&
            !sendCompleted.isCompleted) {
          unawaited(
            sender
                .sendHandshakeOffer(verificationCode)
                .then((_) {
                  if (!sendCompleted.isCompleted) {
                    sendCompleted.complete();
                  }
                })
                .catchError((Object error) {
                  sendError = error;
                  if (!sendCompleted.isCompleted) {
                    sendCompleted.complete();
                  }
                }),
          );
        }
      });
      final receiverSubscription = receiver.events.listen((event) {
        if (event is NearbyTransferHandshakeOfferEvent &&
            !receivedOffer.isCompleted) {
          receivedOffer.complete(event.verificationCode);
        }
      });
      addTearDown(senderSubscription.cancel);
      addTearDown(receiverSubscription.cancel);

      final hosting = await sender.startHostingSession(
        sessionId: 'session-1',
        localDeviceId: 'sender-device',
        localDeviceName: 'Sender',
      );
      await receiver.connectToSession(
        host: InternetAddress.loopbackIPv4.address,
        port: hosting.port,
        localDeviceId: 'receiver-device',
        localDeviceName: 'Receiver',
        expectedSessionId: 'session-1',
      );

      expect(
        await receivedOffer.future.timeout(const Duration(seconds: 5)),
        verificationCode,
      );
      await sendCompleted.future.timeout(const Duration(seconds: 5));
      expect(sendError, isNull);
    },
  );

  test(
    'reconnect after disconnect sends a fresh handshake without sink rebinding',
    () async {
      final sender = _buildAdapter();
      addTearDown(sender.dispose);

      await _expectHandshakeRound(
        sender: sender,
        receiver: _buildAdapter(),
        sessionId: 'session-1',
        verificationCode: const <String>['1', '3'],
      );

      await sender.disconnect();

      await _expectHandshakeRound(
        sender: sender,
        receiver: _buildAdapter(),
        sessionId: 'session-2',
        verificationCode: const <String>['0', '2'],
      );
    },
  );

  test(
    'receiver gets structured folder offer first and sender transfers only explicitly requested files',
    () async {
      final receiveRoot = await Directory.systemTemp.createTemp(
        'landa_nearby_receive_root_',
      );
      final sender = _buildAdapter();
      final receiver = _buildAdapter(receiveRoot: receiveRoot);
      addTearDown(() async {
        sender.dispose();
        receiver.dispose();
        if (await receiveRoot.exists()) {
          await receiveRoot.delete(recursive: true);
        }
      });

      final tempDir = await Directory.systemTemp.createTemp(
        'landa_nearby_offer_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final folder = Directory('${tempDir.path}/Trip');
      final nested = Directory('${folder.path}/docs');
      await nested.create(recursive: true);
      final firstFile = File('${folder.path}/photo.png');
      final secondFile = File('${nested.path}/notes.txt');
      await firstFile.writeAsBytes(
        Uint8List.fromList(List<int>.filled(16, 42)),
      );
      await secondFile.writeAsString('hello nearby transfer');

      final offered = Completer<NearbyTransferIncomingSelectionOfferedEvent>();
      final completed = Completer<NearbyTransferTransferCompletedEvent>();
      final receiverSubscription = receiver.events.listen((event) {
        if (event is NearbyTransferIncomingSelectionOfferedEvent &&
            !offered.isCompleted) {
          offered.complete(event);
        }
        if (event is NearbyTransferTransferCompletedEvent &&
            event.direction == NearbyTransferProgressDirection.receiving &&
            !completed.isCompleted) {
          completed.complete(event);
        }
      });
      addTearDown(receiverSubscription.cancel);

      final hosting = await sender.startHostingSession(
        sessionId: 'session-selective',
        localDeviceId: 'sender-device',
        localDeviceName: 'Sender',
      );
      await receiver.connectToSession(
        host: InternetAddress.loopbackIPv4.address,
        port: hosting.port,
        localDeviceId: 'receiver-device',
        localDeviceName: 'Receiver',
        expectedSessionId: 'session-selective',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sender.sendSelection(
        NearbyTransferSelection(
          label: 'Trip',
          entries: <NearbyTransferPickedEntry>[
            NearbyTransferPickedEntry(
              sourcePath: firstFile.path,
              relativePath: 'Trip/photo.png',
              sizeBytes: await firstFile.length(),
            ),
            NearbyTransferPickedEntry(
              sourcePath: secondFile.path,
              relativePath: 'Trip/docs/notes.txt',
              sizeBytes: await secondFile.length(),
            ),
          ],
        ),
      );

      final offer = await offered.future.timeout(const Duration(seconds: 5));
      expect(offer.roots, hasLength(1));
      expect(offer.roots.single.name, 'Trip');
      expect(offer.roots.single.isDirectory, isTrue);
      expect(offer.roots.single.children, hasLength(2));
      final docsFolder = offer.roots.single.children.singleWhere(
        (node) => node.name == 'docs',
      );
      expect(docsFolder.isDirectory, isTrue);
      expect(docsFolder.children.single.name, 'notes.txt');
      expect(offer.files, hasLength(2));

      final requestedFile = offer.files.singleWhere(
        (file) => file.relativePath == 'Trip/docs/notes.txt',
      );
      await receiver.requestIncomingSelectionDownload(
        requestId: offer.requestId,
        fileIds: <String>[requestedFile.id],
      );

      final result = await completed.future.timeout(
        const Duration(seconds: 10),
      );
      expect(result.savedPaths, hasLength(1));
      expect(
        result.savedPaths.single,
        endsWith(p.join('Trip', 'docs', 'notes.txt')),
      );
    },
  );

  test(
    'receiver can request text preview before download without starting transfer',
    () async {
      final sender = _buildAdapter();
      final receiver = _buildAdapter();
      addTearDown(() async {
        sender.dispose();
        receiver.dispose();
      });

      final tempDir = await Directory.systemTemp.createTemp(
        'landa_nearby_preview_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final textFile = File('${tempDir.path}/notes.txt');
      await textFile.writeAsString('preview body');

      final offered = Completer<NearbyTransferIncomingSelectionOfferedEvent>();
      final previewReady = Completer<NearbyTransferRemotePreviewReadyEvent>();
      final receiverSubscription = receiver.events.listen((event) {
        if (event is NearbyTransferIncomingSelectionOfferedEvent &&
            !offered.isCompleted) {
          offered.complete(event);
        }
        if (event is NearbyTransferRemotePreviewReadyEvent &&
            !previewReady.isCompleted) {
          previewReady.complete(event);
        }
      });
      addTearDown(receiverSubscription.cancel);

      final hosting = await sender.startHostingSession(
        sessionId: 'session-preview',
        localDeviceId: 'sender-device',
        localDeviceName: 'Sender',
      );
      await receiver.connectToSession(
        host: InternetAddress.loopbackIPv4.address,
        port: hosting.port,
        localDeviceId: 'receiver-device',
        localDeviceName: 'Receiver',
        expectedSessionId: 'session-preview',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sender.sendSelection(
        NearbyTransferSelection(
          label: 'Preview offer',
          entries: <NearbyTransferPickedEntry>[
            NearbyTransferPickedEntry(
              sourcePath: textFile.path,
              relativePath: 'notes.txt',
              sizeBytes: await textFile.length(),
            ),
          ],
        ),
      );

      final offer = await offered.future.timeout(const Duration(seconds: 5));
      await receiver.requestIncomingSelectionPreview(
        requestId: offer.requestId,
        fileId: offer.files.single.id,
      );

      final preview = await previewReady.future.timeout(
        const Duration(seconds: 5),
      );
      expect(preview.preview.kind, NearbyTransferRemotePreviewKind.text);
      expect(preview.preview.textContent, 'preview body');
    },
  );
}

Future<void> _expectHandshakeRound({
  required LanNearbyTransportAdapter sender,
  required LanNearbyTransportAdapter receiver,
  required String sessionId,
  required List<String> verificationCode,
}) async {
  addTearDown(receiver.dispose);

  final sendCompleted = Completer<void>();
  final receivedOffer = Completer<List<String>>();
  Object? sendError;

  final senderSubscription = sender.events.listen((event) {
    if (event is NearbyTransferConnectedEvent && !sendCompleted.isCompleted) {
      unawaited(
        sender
            .sendHandshakeOffer(verificationCode)
            .then((_) {
              if (!sendCompleted.isCompleted) {
                sendCompleted.complete();
              }
            })
            .catchError((Object error) {
              sendError = error;
              if (!sendCompleted.isCompleted) {
                sendCompleted.complete();
              }
            }),
      );
    }
  });
  final receiverSubscription = receiver.events.listen((event) {
    if (event is NearbyTransferHandshakeOfferEvent &&
        !receivedOffer.isCompleted) {
      receivedOffer.complete(event.verificationCode);
    }
  });
  addTearDown(senderSubscription.cancel);
  addTearDown(receiverSubscription.cancel);

  final hosting = await sender.startHostingSession(
    sessionId: sessionId,
    localDeviceId: 'sender-device',
    localDeviceName: 'Sender',
  );
  await receiver.connectToSession(
    host: InternetAddress.loopbackIPv4.address,
    port: hosting.port,
    localDeviceId: 'receiver-device',
    localDeviceName: 'Receiver',
    expectedSessionId: sessionId,
  );

  expect(
    await receivedOffer.future.timeout(const Duration(seconds: 5)),
    verificationCode,
  );
  await sendCompleted.future.timeout(const Duration(seconds: 5));
  expect(sendError, isNull);

  await receiver.disconnect();
}

LanNearbyTransportAdapter _buildAdapter({Directory? receiveRoot}) {
  return LanNearbyTransportAdapter(
    fileHashService: FileHashService(),
    fileTransferService: FileTransferService(),
    storageService: NearbyTransferStorageService(
      transferStorageService: receiveRoot == null
          ? TransferStorageService()
          : _TestTransferStorageService(receiveRoot),
    ),
    preferredPort: 0,
  );
}

class _TestTransferStorageService extends TransferStorageService {
  _TestTransferStorageService(this.receiveRoot);

  final Directory receiveRoot;

  @override
  Future<Directory> resolveReceiveDirectory({
    String appFolderName = 'Landa',
  }) async {
    final target = Directory('${receiveRoot.path}/$appFolderName');
    await target.create(recursive: true);
    return target;
  }
}

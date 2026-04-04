import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/data/lan_nearby_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_storage_service.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

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
      const emojiSequence = <String>['🔥', '🌊', '🛰️', '🪵', '🎯'];

      final senderSubscription = sender.events.listen((event) {
        if (event is NearbyTransferConnectedEvent &&
            !sendCompleted.isCompleted) {
          unawaited(
            sender
                .sendHandshakeOffer(emojiSequence)
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
          receivedOffer.complete(event.emojiSequence);
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
        emojiSequence,
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
        emojiSequence: const <String>['😀', '🚀', '🌿', '🎧', '📦'],
      );

      await sender.disconnect();

      await _expectHandshakeRound(
        sender: sender,
        receiver: _buildAdapter(),
        sessionId: 'session-2',
        emojiSequence: const <String>['🍀', '🛰️', '🎲', '🛟', '🧭'],
      );
    },
  );
}

Future<void> _expectHandshakeRound({
  required LanNearbyTransportAdapter sender,
  required LanNearbyTransportAdapter receiver,
  required String sessionId,
  required List<String> emojiSequence,
}) async {
  addTearDown(receiver.dispose);

  final sendCompleted = Completer<void>();
  final receivedOffer = Completer<List<String>>();
  Object? sendError;

  final senderSubscription = sender.events.listen((event) {
    if (event is NearbyTransferConnectedEvent && !sendCompleted.isCompleted) {
      unawaited(
        sender
            .sendHandshakeOffer(emojiSequence)
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
      receivedOffer.complete(event.emojiSequence);
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
    emojiSequence,
  );
  await sendCompleted.future.timeout(const Duration(seconds: 5));
  expect(sendError, isNull);

  await receiver.disconnect();
}

LanNearbyTransportAdapter _buildAdapter() {
  return LanNearbyTransportAdapter(
    fileHashService: FileHashService(),
    fileTransferService: FileTransferService(),
    storageService: NearbyTransferStorageService(
      transferStorageService: TransferStorageService(),
    ),
    preferredPort: 0,
  );
}

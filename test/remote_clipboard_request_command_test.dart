import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/application/remote_clipboard_projection_store.dart';
import 'package:landa/features/discovery/application/remote_clipboard_request_command.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';

void main() {
  test(
    'rejects non-Landa devices before starting projection request',
    () async {
      final store = RemoteClipboardProjectionStore(
        fileHashService: FileHashService(),
      );
      final sentQueries = <_SentClipboardQuery>[];
      final command = _buildCommand(
        store: store,
        sentQueries: sentQueries,
        isTrustedMac: (_) => true,
      );

      final result = await command.request(
        DiscoveredDevice(
          ip: '192.168.1.20',
          isAppDetected: false,
          lastSeen: DateTime(2026),
        ),
      );

      expect(
        result.errorMessage,
        'Remote clipboard is available only for Landa devices.',
      );
      expect(sentQueries, isEmpty);
      expect(store.isLoading, isFalse);
    },
  );

  test('rejects untrusted devices before sending query', () async {
    final store = RemoteClipboardProjectionStore(
      fileHashService: FileHashService(),
    );
    final sentQueries = <_SentClipboardQuery>[];
    final command = _buildCommand(
      store: store,
      sentQueries: sentQueries,
      isTrustedMac: (_) => false,
    );

    final result = await command.request(
      DiscoveredDevice(
        ip: '192.168.1.20',
        macAddress: 'AA-BB-CC-DD-EE-FF',
        isAppDetected: true,
        lastSeen: DateTime(2026),
      ),
    );

    expect(
      result.errorMessage,
      'Remote clipboard is available only for confirmed friends.',
    );
    expect(sentQueries, isEmpty);
    expect(store.isLoading, isFalse);
  });

  test('sends query, applies catalog entries, and finishes loading', () async {
    final store = RemoteClipboardProjectionStore(
      fileHashService: FileHashService(),
    );
    final sentQueries = <_SentClipboardQuery>[];
    late RemoteClipboardRequestCommand command;
    command = _buildCommand(
      store: store,
      sentQueries: sentQueries,
      isTrustedMac: (mac) => mac == 'aa:bb:cc:dd:ee:ff',
      onSend: ({required requestId, required targetIp}) {
        store.applyCatalog(
          ClipboardCatalogEvent(
            requestId: requestId,
            ownerIp: targetIp,
            ownerName: 'Laptop',
            ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
            observedAt: DateTime(2026),
            entries: <ClipboardCatalogItem>[
              ClipboardCatalogItem(
                id: 'entry-1',
                entryType: 'text',
                textValue: 'hello',
                createdAtMs: 1,
              ),
            ],
          ),
        );
      },
    );

    final result = await command.request(
      DiscoveredDevice(
        ip: '192.168.1.20',
        macAddress: 'AA-BB-CC-DD-EE-FF',
        deviceName: 'Laptop',
        isAppDetected: true,
        lastSeen: DateTime(2026),
      ),
    );

    expect(result.errorMessage, isNull);
    expect(result.infoMessage, isNull);
    expect(sentQueries, hasLength(1));
    expect(sentQueries.single.targetIp, '192.168.1.20');
    expect(sentQueries.single.requesterName, 'Local');
    expect(sentQueries.single.requesterMacAddress, '11:22:33:44:55:66');
    expect(sentQueries.single.maxEntries, 12);
    expect(store.entriesFor('192.168.1.20').single.textValue, 'hello');
    expect(store.isLoading, isFalse);
  });

  test('reports empty remote clipboard when no entries arrive', () async {
    final store = RemoteClipboardProjectionStore(
      fileHashService: FileHashService(),
    );
    final sentQueries = <_SentClipboardQuery>[];
    final command = _buildCommand(
      store: store,
      sentQueries: sentQueries,
      isTrustedMac: (_) => true,
    );

    final result = await command.request(
      DiscoveredDevice(
        ip: '192.168.1.20',
        macAddress: 'AA-BB-CC-DD-EE-FF',
        deviceName: 'Laptop',
        isAppDetected: true,
        lastSeen: DateTime(2026),
      ),
    );

    expect(result.errorMessage, isNull);
    expect(result.infoMessage, 'Clipboard history from Laptop is empty.');
    expect(sentQueries, hasLength(1));
    expect(store.isLoading, isFalse);
  });
}

RemoteClipboardRequestCommand _buildCommand({
  required RemoteClipboardProjectionStore store,
  required List<_SentClipboardQuery> sentQueries,
  required bool Function(String? normalizedMac) isTrustedMac,
  void Function({required String requestId, required String targetIp})? onSend,
}) {
  return RemoteClipboardRequestCommand(
    remoteClipboardProjectionStore: store,
    isTrustedMac: isTrustedMac,
    localDeviceMacProvider: () => '11:22:33:44:55:66',
    localNameProvider: () => 'Local',
    settingsProvider: () =>
        AppSettings.defaults.copyWith(clipboardHistoryMaxEntries: 12),
    responseWindow: Duration.zero,
    sendClipboardQuery:
        ({
          required targetIp,
          required requestId,
          required requesterName,
          required requesterMacAddress,
          required maxEntries,
        }) async {
          sentQueries.add(
            _SentClipboardQuery(
              targetIp: targetIp,
              requestId: requestId,
              requesterName: requesterName,
              requesterMacAddress: requesterMacAddress,
              maxEntries: maxEntries,
            ),
          );
          onSend?.call(requestId: requestId, targetIp: targetIp);
        },
  );
}

class _SentClipboardQuery {
  const _SentClipboardQuery({
    required this.targetIp,
    required this.requestId,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.maxEntries,
  });

  final String targetIp;
  final String requestId;
  final String requesterName;
  final String requesterMacAddress;
  final int maxEntries;
}

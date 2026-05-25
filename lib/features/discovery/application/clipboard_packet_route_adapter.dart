import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../../clipboard/application/clipboard_history_store.dart';
import '../../clipboard/application/remote_clipboard_projection_store.dart';
import '../../clipboard/domain/clipboard_entry.dart';
import '../../settings/domain/app_settings.dart';
import '../data/device_alias_repository.dart';
import '../data/lan_discovery_service.dart';
import '../data/lan_packet_codec.dart';
import '../data/lan_protocol_events.dart';

class ClipboardCatalogRouteResult {
  const ClipboardCatalogRouteResult({
    required this.ownerIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.observedAt,
  });

  final String ownerIp;
  final String ownerName;
  final String ownerMacAddress;
  final DateTime observedAt;
}

class ClipboardPacketRouteAdapter {
  ClipboardPacketRouteAdapter({
    required LanDiscoveryService lanDiscoveryService,
    required ClipboardHistoryStore clipboardHistoryStore,
    required RemoteClipboardProjectionStore remoteClipboardProjectionStore,
    required AppSettings Function() settingsProvider,
    required String Function() localNameProvider,
    required String Function() localDeviceMacProvider,
    required bool Function(String? normalizedMac) isTrustedMac,
    void Function(String message)? log,
  }) : _lanDiscoveryService = lanDiscoveryService,
       _clipboardHistoryStore = clipboardHistoryStore,
       _remoteClipboardProjectionStore = remoteClipboardProjectionStore,
       _settingsProvider = settingsProvider,
       _localNameProvider = localNameProvider,
       _localDeviceMacProvider = localDeviceMacProvider,
       _isTrustedMac = isTrustedMac,
       _log = log;

  static const int _maxImagePreviewBytes = 22 * 1024;
  static const List<({int longestEdge, int quality})> _imagePreviewProfiles =
      <({int longestEdge, int quality})>[
        (longestEdge: 512, quality: 55),
        (longestEdge: 420, quality: 50),
        (longestEdge: 320, quality: 42),
        (longestEdge: 256, quality: 36),
        (longestEdge: 192, quality: 30),
      ];

  final LanDiscoveryService _lanDiscoveryService;
  final ClipboardHistoryStore _clipboardHistoryStore;
  final RemoteClipboardProjectionStore _remoteClipboardProjectionStore;
  final AppSettings Function() _settingsProvider;
  final String Function() _localNameProvider;
  final String Function() _localDeviceMacProvider;
  final bool Function(String? normalizedMac) _isTrustedMac;
  final void Function(String message)? _log;

  Future<void> handleClipboardQuery(ClipboardQueryEvent event) async {
    final requesterMac = DeviceAliasRepository.normalizeMac(
      event.requesterMacAddress,
    );
    if (!_isTrustedMac(requesterMac)) {
      _log?.call(
        'Clipboard query from ${event.requesterIp} ignored: not a friend.',
      );
      return;
    }

    final settings = _settingsProvider();
    final safeLimit = event.maxEntries <= 0
        ? (settings.clipboardHistoryMaxEntries <= 0
              ? 120
              : settings.clipboardHistoryMaxEntries)
        : event.maxEntries;

    final sourceEntries = _clipboardHistoryStore.listRecent(limit: safeLimit);
    final entries = <ClipboardCatalogItem>[];
    for (final item in sourceEntries) {
      if (item.type == ClipboardEntryType.text) {
        final text = item.textValue ?? '';
        final clipped = text.length > 6000 ? text.substring(0, 6000) : text;
        entries.add(
          ClipboardCatalogItem(
            id: item.id,
            entryType: item.type.value,
            createdAtMs: item.createdAt.millisecondsSinceEpoch,
            textValue: clipped,
          ),
        );
        continue;
      }

      final imagePath = item.imagePath;
      if (imagePath == null || imagePath.trim().isEmpty) {
        continue;
      }
      final previewBase64 = await _encodeImagePreviewBase64(imagePath);
      if (previewBase64 == null) {
        continue;
      }
      entries.add(
        ClipboardCatalogItem(
          id: item.id,
          entryType: item.type.value,
          createdAtMs: item.createdAt.millisecondsSinceEpoch,
          imagePreviewBase64: previewBase64,
        ),
      );
    }

    try {
      await _lanDiscoveryService.sendClipboardCatalog(
        targetIp: event.requesterIp,
        requestId: event.requestId,
        ownerName: _localNameProvider(),
        ownerMacAddress: _localDeviceMacProvider(),
        entries: entries,
      );
    } catch (error) {
      _log?.call('Failed to send clipboard catalog: $error');
    }
  }

  ClipboardCatalogRouteResult? handleClipboardCatalog(
    ClipboardCatalogEvent event,
  ) {
    final applied = _remoteClipboardProjectionStore.applyCatalog(event);
    if (!applied) {
      return null;
    }

    return ClipboardCatalogRouteResult(
      ownerIp: event.ownerIp,
      ownerName: event.ownerName,
      ownerMacAddress: event.ownerMacAddress,
      observedAt: event.observedAt,
    );
  }

  Future<void> captureSnapshot() async {
    try {
      await _clipboardHistoryStore.captureSnapshot(
        maxEntries: _settingsProvider().clipboardHistoryMaxEntries,
      );
    } catch (error) {
      _log?.call('Clipboard capture failed: $error');
    }
  }

  Future<void> trimHistoryToSettingsLimit() {
    return _clipboardHistoryStore.trimHistory(
      _settingsProvider().clipboardHistoryMaxEntries,
    );
  }

  Future<String?> _encodeImagePreviewBase64(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return null;
      }
      List<int>? encoded;
      for (final profile in _imagePreviewProfiles) {
        final resized = _resizeImagePreview(
          decoded,
          longestEdge: profile.longestEdge,
        );
        final candidate = img.encodeJpg(resized, quality: profile.quality);
        encoded = candidate;
        if (candidate.length <= _maxImagePreviewBytes) {
          break;
        }
      }
      if (encoded == null || encoded.isEmpty) {
        return null;
      }
      return base64Encode(encoded);
    } catch (_) {
      return null;
    }
  }

  img.Image _resizeImagePreview(img.Image source, {required int longestEdge}) {
    final longest = math.max(source.width, source.height);
    if (longest <= longestEdge) {
      return source;
    }
    return img.copyResize(
      source,
      width: source.width >= source.height ? longestEdge : null,
      height: source.height > source.width ? longestEdge : null,
    );
  }
}

import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../discovery/data/lan_packet_codec.dart';
import '../../discovery/data/lan_protocol_events.dart';
import '../../transfer/data/file_hash_service.dart';
import '../domain/clipboard_entry.dart';

class RemoteClipboardProjectionStore extends ChangeNotifier {
  RemoteClipboardProjectionStore({required FileHashService fileHashService})
    : _fileHashService = fileHashService;

  final FileHashService _fileHashService;

  final Map<String, List<RemoteClipboardEntry>> _entriesByOwnerIp =
      <String, List<RemoteClipboardEntry>>{};
  final Map<String, UnmodifiableListView<RemoteClipboardEntry>>
  _entryViewsByOwnerIp = <String, UnmodifiableListView<RemoteClipboardEntry>>{};
  bool _isLoading = false;
  String? _loadingOwnerIp;
  String? _activeRequestId;

  bool get isLoading => _isLoading;
  String? get loadingOwnerIp => _loadingOwnerIp;

  List<RemoteClipboardEntry> entriesFor(String ownerIp) {
    return _entryViewsByOwnerIp[ownerIp] ?? const <RemoteClipboardEntry>[];
  }

  bool hasEntriesFor(String ownerIp) {
    return (_entriesByOwnerIp[ownerIp] ?? const <RemoteClipboardEntry>[])
        .isNotEmpty;
  }

  bool isLoadingFor(String ownerIp) {
    return _isLoading && _loadingOwnerIp == ownerIp;
  }

  String beginRequest({
    required String ownerIp,
    required String localDeviceMac,
  }) {
    final requestId = _fileHashService.buildStableId(
      'clipboard-query|${DateTime.now().microsecondsSinceEpoch}|$ownerIp|$localDeviceMac',
    );
    _activeRequestId = requestId;
    _loadingOwnerIp = ownerIp;
    _isLoading = true;
    _entriesByOwnerIp.remove(ownerIp);
    _entryViewsByOwnerIp.remove(ownerIp);
    notifyListeners();
    return requestId;
  }

  bool applyCatalog(ClipboardCatalogEvent event) {
    if (_activeRequestId != null && event.requestId != _activeRequestId) {
      return false;
    }

    final mapped = _mapEntries(event.entries);
    mapped.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _entriesByOwnerIp[event.ownerIp] = mapped;
    _entryViewsByOwnerIp[event.ownerIp] =
        UnmodifiableListView<RemoteClipboardEntry>(mapped);
    notifyListeners();
    return true;
  }

  void finishRequest({required String requestId}) {
    if (_activeRequestId != requestId) {
      return;
    }
    _activeRequestId = null;
    _loadingOwnerIp = null;
    _isLoading = false;
    notifyListeners();
  }

  List<RemoteClipboardEntry> _mapEntries(List<ClipboardCatalogItem> items) {
    final mapped = <RemoteClipboardEntry>[];
    for (final item in items) {
      final type = ClipboardEntryTypeX.fromValue(item.entryType);
      Uint8List? imageBytes;
      if (type == ClipboardEntryType.image) {
        final encoded = item.imagePreviewBase64;
        if (encoded == null || encoded.trim().isEmpty) {
          continue;
        }
        try {
          imageBytes = base64Decode(encoded);
        } catch (error) {
          _log('Failed to decode remote clipboard image ${item.id}: $error');
          continue;
        }
      }
      mapped.add(
        RemoteClipboardEntry(
          id: item.id,
          type: type,
          createdAt: DateTime.fromMillisecondsSinceEpoch(item.createdAtMs),
          textValue: item.textValue,
          imageBytes: imageBytes,
        ),
      );
    }
    return mapped;
  }

  void _log(String message) {
    developer.log(message, name: 'RemoteClipboardProjectionStore');
  }
}

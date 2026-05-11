import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../discovery/data/lan_packet_codec_models.dart';
import 'remote_share_access_session_models.dart';

class RemoteShareAccessSnapshotParser {
  const RemoteShareAccessSnapshotParser();

  Future<RemoteShareAccessSnapshotPayload> parse(
    List<String> savedPaths,
  ) async {
    Object? lastError;
    for (final path in savedPaths) {
      try {
        final file = File(path);
        if (!await file.exists()) {
          continue;
        }
        final rawBytes = await file.readAsBytes();
        final decodedBytes = p.extension(path).toLowerCase() == '.gz'
            ? gzip.decode(rawBytes)
            : rawBytes;
        final decoded = jsonDecode(utf8.decode(decodedBytes));
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final ownerName = (decoded['ownerName'] as String? ?? '').trim();
        final ownerMacAddress = (decoded['ownerMacAddress'] as String? ?? '')
            .trim();
        final entriesRaw = decoded['entries'];
        if (ownerName.isEmpty ||
            ownerMacAddress.isEmpty ||
            entriesRaw is! List<dynamic>) {
          continue;
        }
        final entries = <SharedCatalogEntryItem>[];
        for (final entry in entriesRaw) {
          if (entry is! Map<String, dynamic>) {
            continue;
          }
          final parsed = SharedCatalogEntryItem.fromJson(entry);
          if (parsed != null) {
            entries.add(parsed);
          }
        }
        return RemoteShareAccessSnapshotPayload(
          ownerName: ownerName,
          ownerMacAddress: ownerMacAddress,
          entries: entries,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(
      'Не удалось прочитать snapshot общего доступа.'
      '${lastError == null ? '' : ' $lastError'}',
    );
  }
}

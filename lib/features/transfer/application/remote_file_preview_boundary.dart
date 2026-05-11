import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import '../../discovery/data/device_alias_repository.dart';
import '../../discovery/data/lan_discovery_service.dart';
import '../../discovery/data/lan_packet_codec_models.dart';
import '../../discovery/data/lan_protocol_events.dart';
import '../../files/application/preview_cache_owner.dart';
import '../../settings/domain/app_settings.dart';
import '../data/file_hash_service.dart';
import '../domain/shared_folder_cache.dart';
import 'shared_download_boundary.dart';
import 'transfer_path_policy.dart';
import 'transfer_session_coordinator.dart';

class RemoteFilePreviewBoundary {
  RemoteFilePreviewBoundary({
    required LanDiscoveryService lanDiscoveryService,
    required FileHashService fileHashService,
    required PreviewCacheOwner previewCacheOwner,
    required AppSettings Function() settingsProvider,
    required String Function() localNameProvider,
    required String Function() localDeviceMacProvider,
    required String? Function({
      required String ownerIp,
      required String cacheId,
    })
    resolveRemoteOwnerMac,
    required void Function(TransferSessionNotice notice) publishNotice,
    this.pendingRemotePreviewTtl = const Duration(minutes: 1),
    this.previewRequestTimeout = const Duration(seconds: 45),
    TransferPathPolicy pathPolicy = const TransferPathPolicy(),
  }) : _lanDiscoveryService = lanDiscoveryService,
       _fileHashService = fileHashService,
       _previewCacheOwner = previewCacheOwner,
       _settingsProvider = settingsProvider,
       _localNameProvider = localNameProvider,
       _localDeviceMacProvider = localDeviceMacProvider,
       _resolveRemoteOwnerMac = resolveRemoteOwnerMac,
       _publishNotice = publishNotice,
       _pathPolicy = pathPolicy;

  final LanDiscoveryService _lanDiscoveryService;
  final FileHashService _fileHashService;
  final PreviewCacheOwner _previewCacheOwner;
  final AppSettings Function() _settingsProvider;
  final String Function() _localNameProvider;
  final String Function() _localDeviceMacProvider;
  final String? Function({required String ownerIp, required String cacheId})
  _resolveRemoteOwnerMac;
  final void Function(TransferSessionNotice notice) _publishNotice;
  final TransferPathPolicy _pathPolicy;

  final Map<String, _PendingRemotePreviewIntent> _pendingRemotePreviewsByKey =
      <String, _PendingRemotePreviewIntent>{};
  final Map<String, Completer<String?>> _previewResultCompletersByRequestId =
      <String, Completer<String?>>{};

  final Duration pendingRemotePreviewTtl;
  final Duration previewRequestTimeout;

  Future<String?> requestRemoteFilePreview({
    required String ownerIp,
    required String ownerName,
    required String cacheId,
    required String relativePath,
  }) async {
    final normalizedRelativePath = _pathPolicy.normalizeForMatch(relativePath);
    if (normalizedRelativePath.isEmpty) {
      _publishNotice(
        const TransferSessionNotice(errorMessage: 'Preview path is empty.'),
      );
      return null;
    }

    await cleanupPreviewCacheBySettings();
    purgeExpiredPendingRemotePreviews();
    final pendingKey = _pendingRemotePreviewKey(
      ownerIp: ownerIp,
      cacheId: cacheId,
      normalizedRelativePath: normalizedRelativePath,
    );

    final existing = _pendingRemotePreviewsByKey[pendingKey];
    if (existing != null) {
      return existing.completer.future;
    }

    final previewCompleter = Completer<String?>();
    _pendingRemotePreviewsByKey[pendingKey] = _PendingRemotePreviewIntent(
      ownerIp: ownerIp,
      ownerMacAddress: _resolveRemoteOwnerMac(
        ownerIp: ownerIp,
        cacheId: cacheId,
      ),
      cacheId: cacheId,
      normalizedRelativePath: normalizedRelativePath,
      createdAt: DateTime.now(),
      completer: previewCompleter,
    );

    try {
      final requestId = _fileHashService.buildStableId(
        'preview|$ownerIp|$cacheId|$normalizedRelativePath|'
        '${DateTime.now().microsecondsSinceEpoch}|$_localDeviceMac',
      );
      await _lanDiscoveryService.sendDownloadRequest(
        targetIp: ownerIp,
        requestId: requestId,
        requesterName: _localName,
        requesterMacAddress: _localDeviceMac,
        cacheId: cacheId,
        selectedRelativePaths: <String>[relativePath],
        selectedFolderPrefixes: const <String>[],
        previewMode: true,
      );

      final previewPath = await previewCompleter.future.timeout(
        previewRequestTimeout,
        onTimeout: () => null,
      );
      if (previewPath == null) {
        _publishNotice(
          TransferSessionNotice(
            errorMessage: 'Preview timed out for $ownerName.',
          ),
        );
      }
      return previewPath;
    } catch (error) {
      _log('Failed to request preview: $error');
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Failed to request preview: $error',
        ),
      );
      if (!previewCompleter.isCompleted) {
        previewCompleter.complete(null);
      }
      return null;
    } finally {
      _pendingRemotePreviewsByKey.remove(pendingKey);
    }
  }

  RemoteFilePreviewIntent? consumePendingRemotePreview(
    TransferRequestEvent event,
  ) {
    purgeExpiredPendingRemotePreviews();
    final normalizedSenderMac = DeviceAliasRepository.normalizeMac(
      event.senderMacAddress,
    );

    String? matchedKey;
    for (final entry in _pendingRemotePreviewsByKey.entries) {
      final pending = entry.value;
      if (pending.cacheId != event.sharedCacheId) {
        continue;
      }

      final ipMatches = pending.ownerIp == event.senderIp;
      final macMatches =
          pending.ownerMacAddress != null &&
          normalizedSenderMac != null &&
          pending.ownerMacAddress == normalizedSenderMac;
      if (!ipMatches && !macMatches) {
        continue;
      }

      matchedKey = entry.key;
      break;
    }

    if (matchedKey == null) {
      return null;
    }
    final pending = _pendingRemotePreviewsByKey.remove(matchedKey)!;
    return RemoteFilePreviewIntent(
      normalizedRelativePath: pending.normalizedRelativePath,
      completer: pending.completer,
    );
  }

  void registerPreviewResultCompleter({
    required String requestId,
    required Completer<String?> completer,
  }) {
    _previewResultCompletersByRequestId[requestId] = completer;
  }

  Completer<String?>? takePreviewResultCompleter(String requestId) {
    return _previewResultCompletersByRequestId.remove(requestId);
  }

  void discardPreviewResultCompleter(String requestId) {
    _previewResultCompletersByRequestId.remove(requestId);
  }

  Future<Directory> resolvePreviewArtifactDirectory() {
    return _previewCacheOwner.resolvePreviewArtifactDirectory();
  }

  Future<void> cleanupPreviewCacheBySettings() async {
    try {
      final settings = _settingsProvider();
      await _previewCacheOwner.cleanupPreviewArtifacts(
        maxSizeGb: settings.previewCacheMaxSizeGb,
        maxAgeDays: settings.previewCacheMaxAgeDays,
      );
    } catch (error) {
      _log('Failed to cleanup preview cache: $error');
    }
  }

  Future<List<SharedDownloadPreparedFile>> buildCompressedPreviewFilesForCache(
    SharedFolderCacheRecord cache, {
    Set<String>? relativePathFilter,
  }) async {
    final prepared = await _previewCacheOwner
        .buildCompressedPreviewFilesForCache(
          cache,
          relativePathFilter: relativePathFilter,
        );
    return prepared
        .map(
          (file) => SharedDownloadPreparedFile(
            sourcePath: file.sourcePath,
            announcement: TransferAnnouncementItem(
              fileName: file.fileName,
              sizeBytes: file.sizeBytes,
              sha256: file.sha256,
            ),
            deleteAfterTransfer: file.deleteAfterTransfer,
          ),
        )
        .toList(growable: false);
  }

  void purgeExpiredPendingRemotePreviews() {
    final now = DateTime.now();
    _pendingRemotePreviewsByKey.removeWhere((_, pending) {
      final expired =
          now.difference(pending.createdAt) > pendingRemotePreviewTtl;
      if (expired && !pending.completer.isCompleted) {
        pending.completer.complete(null);
      }
      return expired;
    });
  }

  void dispose() {
    for (final pending in _pendingRemotePreviewsByKey.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete(null);
      }
    }
    _pendingRemotePreviewsByKey.clear();
    for (final completer in _previewResultCompletersByRequestId.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _previewResultCompletersByRequestId.clear();
  }

  String _pendingRemotePreviewKey({
    required String ownerIp,
    required String cacheId,
    required String normalizedRelativePath,
  }) {
    return '$ownerIp|$cacheId|$normalizedRelativePath';
  }

  void _log(String message) {
    developer.log(message, name: 'RemoteFilePreviewBoundary');
  }

  String get _localName => _localNameProvider();

  String get _localDeviceMac => _localDeviceMacProvider();
}

class RemoteFilePreviewIntent {
  const RemoteFilePreviewIntent({
    required this.normalizedRelativePath,
    required this.completer,
  });

  final String normalizedRelativePath;
  final Completer<String?> completer;
}

class _PendingRemotePreviewIntent {
  _PendingRemotePreviewIntent({
    required this.ownerIp,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.normalizedRelativePath,
    required this.createdAt,
    required this.completer,
  });

  final String ownerIp;
  final String? ownerMacAddress;
  final String cacheId;
  final String normalizedRelativePath;
  final DateTime createdAt;
  final Completer<String?> completer;
}

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'app_update_storage_service.dart';
import '../domain/app_update_models.dart';

class AppUpdateDownloadService {
  static const int maxRedirects = 5;
  static const Duration defaultConnectionTimeout = Duration(seconds: 20);
  static const Duration defaultChunkTimeout = Duration(seconds: 60);

  AppUpdateDownloadService({
    required AppUpdateStorageService storageService,
    HttpClient Function()? httpClientFactory,
    Duration connectionTimeout = defaultConnectionTimeout,
    Duration chunkTimeout = defaultChunkTimeout,
  }) : _storageService = storageService,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _connectionTimeout = connectionTimeout,
       _chunkTimeout = chunkTimeout;

  final AppUpdateStorageService _storageService;
  final HttpClient Function() _httpClientFactory;
  final Duration _connectionTimeout;
  final Duration _chunkTimeout;

  Future<File> downloadAsset(
    AppUpdateAsset asset, {
    AppUpdateDownloadProgressCallback? onProgress,
  }) async {
    final initialUri = Uri.tryParse(asset.downloadUrl);
    if (initialUri == null || !_isAllowedAssetUri(initialUri)) {
      throw FormatException(
        'Refusing to download update asset over insecure scheme: '
        '${asset.downloadUrl}',
      );
    }
    final expectedSha256 = asset.sha256.trim().toLowerCase();
    if (expectedSha256.isEmpty) {
      throw StateError(
        'Missing expected SHA-256 checksum for ${asset.fileName}.',
      );
    }

    final client = _httpClientFactory();
    client.connectionTimeout = _connectionTimeout;
    File? partFile;
    try {
      var currentUri = initialUri;
      late final HttpClientResponse response;
      for (var redirectCount = 0; ; redirectCount += 1) {
        if (!_isAllowedAssetUri(currentUri)) {
          throw FormatException(
            'Refusing to follow insecure update redirect: $currentUri',
          );
        }
        final request = await client.getUrl(currentUri).timeout(_chunkTimeout);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'LandaUpdater/1.0');
        final candidateResponse = await request.close().timeout(_chunkTimeout);
        if (_isRedirectStatus(candidateResponse.statusCode)) {
          final location = candidateResponse.headers.value(
            HttpHeaders.locationHeader,
          );
          await candidateResponse.drain<void>().timeout(_chunkTimeout);
          if (location == null || location.trim().isEmpty) {
            throw HttpException(
              'Asset redirect missing Location header '
              '(${candidateResponse.statusCode})',
              uri: currentUri,
            );
          }
          if (redirectCount >= maxRedirects) {
            throw HttpException(
              'Too many redirects while downloading ${asset.fileName}',
              uri: currentUri,
            );
          }
          currentUri = currentUri.resolve(location.trim());
          continue;
        }
        response = candidateResponse;
        break;
      }

      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().timeout(_chunkTimeout);
        throw HttpException(
          'Asset download failed with status ${response.statusCode}',
          uri: currentUri,
        );
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : (asset.size > 0 ? asset.size : null);
      onProgress?.call(0, totalBytes);

      final targetFile = await _storageService.createTargetFile(asset.fileName);
      final stagedFile = File('${targetFile.path}.part');
      partFile = stagedFile;
      if (await stagedFile.exists()) {
        await stagedFile.delete();
      }

      var receivedBytes = 0;
      final sink = stagedFile.openWrite();
      var sinkClosed = false;
      try {
        await for (final chunk in response.timeout(_chunkTimeout)) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(receivedBytes, totalBytes);
        }
        await sink.flush();
        await sink.close();
        sinkClosed = true;
      } finally {
        if (!sinkClosed) {
          try {
            await sink.close();
          } catch (_) {
            // Best-effort close before deleting partial file.
          }
        }
      }

      if (asset.size > 0 && receivedBytes != asset.size) {
        throw StateError(
          'Downloaded update size mismatch for ${asset.fileName}: '
          'expected ${asset.size} bytes, got $receivedBytes bytes.',
        );
      }

      final digest = await sha256.bind(stagedFile.openRead()).first;
      final checksum = digest.toString().toLowerCase();
      if (checksum != expectedSha256) {
        throw StateError(
          'Downloaded update checksum mismatch for ${asset.fileName}.',
        );
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await stagedFile.rename(targetFile.path);
      partFile = null;
      return targetFile;
    } catch (_) {
      if (partFile != null && await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {
          // Best-effort cleanup of partial download.
        }
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static bool _isRedirectStatus(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  static bool _isAllowedAssetUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') {
      return uri.host.trim().isNotEmpty;
    }
    if (scheme == 'http' &&
        (uri.host == '127.0.0.1' ||
            uri.host == 'localhost' ||
            uri.host == '::1')) {
      return true;
    }
    return false;
  }
}

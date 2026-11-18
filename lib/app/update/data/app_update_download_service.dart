import 'dart:io';

import 'package:crypto/crypto.dart';

import 'app_update_storage_service.dart';
import '../domain/app_update_models.dart';

class AppUpdateDownloadService {
  AppUpdateDownloadService({
    required AppUpdateStorageService storageService,
    HttpClient Function()? httpClientFactory,
  }) : _storageService = storageService,
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final AppUpdateStorageService _storageService;
  final HttpClient Function() _httpClientFactory;

  Future<File> downloadAsset(AppUpdateAsset asset) async {
    final uri = Uri.parse(asset.downloadUrl);
    if (!_isAllowedAssetUri(uri)) {
      throw FormatException(
        'Refusing to download update asset over insecure scheme: ${asset.downloadUrl}',
      );
    }
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'LandaUpdater/1.0');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Asset download failed with status ${response.statusCode}',
          uri: uri,
        );
      }

      final targetFile = await _storageService.createTargetFile(asset.fileName);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await response.pipe(targetFile.openWrite());
      final digest = await sha256.bind(targetFile.openRead()).first;
      final checksum = digest.toString().toLowerCase();
      if (checksum != asset.sha256.trim().toLowerCase()) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        throw StateError(
          'Downloaded update checksum mismatch for ${asset.fileName}.',
        );
      }
      return targetFile;
    } finally {
      client.close(force: true);
    }
  }

  static bool _isAllowedAssetUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') {
      return true;
    }
    if (scheme == 'http' &&
        (uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1')) {
      return true;
    }
    return false;
  }
}

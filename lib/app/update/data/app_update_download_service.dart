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
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(Uri.parse(asset.downloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'LandaUpdater/1.0');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Asset download failed with status ${response.statusCode}',
          uri: Uri.parse(asset.downloadUrl),
        );
      }

      final targetFile = await _storageService.createTargetFile(asset.fileName);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await response.pipe(targetFile.openWrite());
      final checksum = sha256
          .convert(await targetFile.readAsBytes())
          .toString();
      if (checksum != asset.sha256) {
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
}

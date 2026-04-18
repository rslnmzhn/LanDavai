import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/data/app_update_download_service.dart';
import 'package:landa/app/update/data/app_update_storage_service.dart';
import 'package:landa/app/update/domain/app_update_models.dart';

void main() {
  late Directory tempDirectory;
  late HttpServer server;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'landa_update_download_',
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('downloads the selected asset and validates its checksum', () async {
    final payload = utf8.encode('landa update payload');
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..add(payload);
      await request.response.close();
    });

    final service = AppUpdateDownloadService(
      storageService: _FakeAppUpdateStorageService(tempDirectory),
    );
    final asset = AppUpdateAsset(
      platform: 'windows',
      arch: 'x86_64',
      format: 'zip',
      primary: true,
      fileName: 'landa-v1.1.0-windows-x64.zip',
      size: payload.length,
      sha256: sha256.convert(payload).toString(),
      downloadUrl:
          'http://${server.address.address}:${server.port}/landa-v1.1.0-windows-x64.zip',
    );

    final file = await service.downloadAsset(asset);

    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), payload);
  });

  test('fails and deletes the file when the checksum does not match', () async {
    final payload = utf8.encode('tampered payload');
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..add(payload);
      await request.response.close();
    });

    final service = AppUpdateDownloadService(
      storageService: _FakeAppUpdateStorageService(tempDirectory),
    );
    final asset = AppUpdateAsset(
      platform: 'android',
      arch: 'arm64-v8a',
      format: 'apk',
      primary: true,
      fileName: 'landa-v1.1.0-android-arm64-v8a.apk',
      size: payload.length,
      sha256: sha256.convert(utf8.encode('expected payload')).toString(),
      downloadUrl:
          'http://${server.address.address}:${server.port}/landa-v1.1.0-android-arm64-v8a.apk',
    );

    await expectLater(
      () => service.downloadAsset(asset),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('checksum mismatch'),
        ),
      ),
    );

    final file = File('${tempDirectory.path}\\${asset.fileName}');
    expect(await file.exists(), isFalse);
  });
}

class _FakeAppUpdateStorageService extends AppUpdateStorageService {
  _FakeAppUpdateStorageService(this.directory);

  final Directory directory;

  @override
  Future<File> createTargetFile(String fileName) async {
    await directory.create(recursive: true);
    return File('${directory.path}\\$fileName');
  }
}

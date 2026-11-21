import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/data/app_update_download_service.dart';
import 'package:landa/app/update/data/app_update_storage_service.dart';
import 'package:landa/app/update/domain/app_update_models.dart';
import 'package:path/path.dart' as p;

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
    expect(await File('${file.path}.part').exists(), isFalse);
  });

  test(
    'follows 302 redirect, reports progress, and cleans up staging file',
    () async {
      final payload = utf8.encode('redirected release asset payload');
      server.listen((request) async {
        if (request.uri.path == '/releases/download/v0.2.4/asset.AppImage') {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(
              HttpHeaders.locationHeader,
              'http://${server.address.address}:${server.port}/cdn/asset.AppImage',
            );
          await request.response.close();
          return;
        }
        if (request.uri.path == '/cdn/asset.AppImage') {
          request.response
            ..statusCode = HttpStatus.ok
            ..contentLength = payload.length
            ..add(payload.sublist(0, 10))
            ..add(payload.sublist(10));
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final service = AppUpdateDownloadService(
        storageService: AppUpdateStorageService(
          updateDirectoryResolver: () async => tempDirectory,
        ),
      );
      final asset = AppUpdateAsset(
        platform: 'linux',
        arch: 'x86_64',
        format: 'appimage',
        primary: true,
        fileName: 'landa-v0.2.4-linux-x86_64.AppImage',
        size: payload.length,
        sha256: sha256.convert(payload).toString().toUpperCase(),
        downloadUrl:
            'http://${server.address.address}:${server.port}/releases/download/v0.2.4/asset.AppImage',
      );

      final progressEvents = <(int, int?)>[];
      final file = await service.downloadAsset(
        asset,
        onProgress: (received, total) {
          progressEvents.add((received, total));
        },
      );

      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), payload);
      expect(await File('${file.path}.part').exists(), isFalse);
      expect(progressEvents, isNotEmpty);
      expect(progressEvents.last, (payload.length, payload.length));
    },
  );

  test(
    'cleans up partial file on failure and succeeds on subsequent retry',
    () async {
      final payload = utf8.encode('complete valid update payload');
      var attempt = 0;
      server.listen((request) async {
        attempt += 1;
        if (attempt == 1) {
          request.response
            ..statusCode = HttpStatus.ok
            ..add(payload.sublist(0, 8));
          await request.response.close();
          return;
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = payload.length
          ..add(payload);
        await request.response.close();
      });

      final service = AppUpdateDownloadService(
        storageService: AppUpdateStorageService(
          updateDirectoryResolver: () async => tempDirectory,
        ),
      );
      final asset = AppUpdateAsset(
        platform: 'windows',
        arch: 'x86_64',
        format: 'zip',
        primary: true,
        fileName: 'landa-v0.2.4-windows-x64.zip',
        size: payload.length,
        sha256: sha256.convert(payload).toString(),
        downloadUrl:
            'http://${server.address.address}:${server.port}/landa-v0.2.4-windows-x64.zip',
      );

      await expectLater(
        () => service.downloadAsset(asset),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('size mismatch'),
          ),
        ),
      );

      final targetPath = p.join(tempDirectory.path, asset.fileName);
      expect(await File(targetPath).exists(), isFalse);
      expect(await File('$targetPath.part').exists(), isFalse);

      final retriedFile = await service.downloadAsset(asset);
      expect(await retriedFile.exists(), isTrue);
      expect(await retriedFile.readAsBytes(), payload);
    },
  );

  test('rejects non-HTTPS non-loopback download URLs', () async {
    final service = AppUpdateDownloadService(
      storageService: AppUpdateStorageService(
        updateDirectoryResolver: () async => tempDirectory,
      ),
    );
    const asset = AppUpdateAsset(
      platform: 'windows',
      arch: 'x86_64',
      format: 'zip',
      primary: true,
      fileName: 'landa-v0.2.4-windows-x64.zip',
      size: 10,
      sha256: 'abc',
      downloadUrl: 'http://example.com/landa-v0.2.4-windows-x64.zip',
    );

    await expectLater(
      () => service.downloadAsset(asset),
      throwsA(isA<FormatException>()),
    );
  });

  test('AppUpdateStorageService sanitizes dot and dot-dot filenames', () async {
    final storageService = AppUpdateStorageService(
      updateDirectoryResolver: () async => tempDirectory,
    );

    final dotFile = await storageService.createTargetFile('.');
    final dotDotFile = await storageService.createTargetFile('..');

    expect(p.basename(dotFile.path), 'update.bin');
    expect(p.basename(dotDotFile.path), 'update.bin');
    expect(p.isWithin(tempDirectory.path, dotFile.path), isTrue);
    expect(p.isWithin(tempDirectory.path, dotDotFile.path), isTrue);
  });

  test(
    'exits with TimeoutException on stalled redirect body and succeeds on retry',
    () async {
      final payload = utf8.encode('recovered after stalled redirect');
      final stalledResponses = <HttpResponse>[];
      addTearDown(() async {
        for (final response in stalledResponses) {
          try {
            await response.close().timeout(const Duration(milliseconds: 50));
          } catch (_) {}
        }
      });

      var attempt = 0;
      server.listen((request) async {
        if (request.uri.path == '/releases/download/v0.2.4/asset.zip') {
          attempt += 1;
          if (attempt == 1) {
            request.response
              ..bufferOutput = false
              ..statusCode = HttpStatus.found
              ..contentLength = 64
              ..headers.set(
                HttpHeaders.locationHeader,
                'http://${server.address.address}:${server.port}/cdn/asset.zip',
              )
              ..add(const <int>[1]);
            await request.response.flush();
            stalledResponses.add(request.response);
            return;
          }
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(
              HttpHeaders.locationHeader,
              'http://${server.address.address}:${server.port}/cdn/asset.zip',
            );
          await request.response.close();
          return;
        }
        if (request.uri.path == '/cdn/asset.zip') {
          request.response
            ..statusCode = HttpStatus.ok
            ..contentLength = payload.length
            ..add(payload);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final service = AppUpdateDownloadService(
        storageService: AppUpdateStorageService(
          updateDirectoryResolver: () async => tempDirectory,
        ),
        chunkTimeout: const Duration(milliseconds: 80),
      );
      final asset = AppUpdateAsset(
        platform: 'windows',
        arch: 'x86_64',
        format: 'zip',
        primary: true,
        fileName: 'landa-v0.2.4-windows-x64.zip',
        size: payload.length,
        sha256: sha256.convert(payload).toString(),
        downloadUrl:
            'http://${server.address.address}:${server.port}/releases/download/v0.2.4/asset.zip',
      );

      await expectLater(
        () => service.downloadAsset(asset),
        throwsA(isA<TimeoutException>()),
      );

      final retriedFile = await service.downloadAsset(asset);
      expect(await retriedFile.exists(), isTrue);
      expect(await retriedFile.readAsBytes(), payload);
    },
  );

  test(
    'exits with TimeoutException on stalled non-200 error body and succeeds on retry',
    () async {
      final payload = utf8.encode('recovered after stalled error body');
      final stalledResponses = <HttpResponse>[];
      addTearDown(() async {
        for (final response in stalledResponses) {
          try {
            await response.close().timeout(const Duration(milliseconds: 50));
          } catch (_) {}
        }
      });

      var attempt = 0;
      server.listen((request) async {
        attempt += 1;
        if (attempt == 1) {
          request.response
            ..bufferOutput = false
            ..statusCode = HttpStatus.serviceUnavailable
            ..contentLength = 64
            ..add(const <int>[1]);
          await request.response.flush();
          stalledResponses.add(request.response);
          return;
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = payload.length
          ..add(payload);
        await request.response.close();
      });

      final service = AppUpdateDownloadService(
        storageService: AppUpdateStorageService(
          updateDirectoryResolver: () async => tempDirectory,
        ),
        chunkTimeout: const Duration(milliseconds: 80),
      );
      final asset = AppUpdateAsset(
        platform: 'windows',
        arch: 'x86_64',
        format: 'zip',
        primary: true,
        fileName: 'landa-v0.2.4-windows-x64.zip',
        size: payload.length,
        sha256: sha256.convert(payload).toString(),
        downloadUrl:
            'http://${server.address.address}:${server.port}/landa-v0.2.4-windows-x64.zip',
      );

      await expectLater(
        () => service.downloadAsset(asset),
        throwsA(isA<TimeoutException>()),
      );

      final retriedFile = await service.downloadAsset(asset);
      expect(await retriedFile.exists(), isTrue);
      expect(await retriedFile.readAsBytes(), payload);
    },
  );

  test(
    'exits with TimeoutException on stalled 200 body, cleans up part file, and succeeds on retry',
    () async {
      final payload = utf8.encode('recovered after stalled 200 body');
      final stalledResponses = <HttpResponse>[];
      addTearDown(() async {
        for (final response in stalledResponses) {
          try {
            await response.close().timeout(const Duration(milliseconds: 50));
          } catch (_) {}
        }
      });

      var attempt = 0;
      server.listen((request) async {
        attempt += 1;
        if (attempt == 1) {
          request.response
            ..bufferOutput = false
            ..statusCode = HttpStatus.ok
            ..contentLength = payload.length
            ..add(payload.sublist(0, 5));
          await request.response.flush();
          stalledResponses.add(request.response);
          return;
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = payload.length
          ..add(payload);
        await request.response.close();
      });

      final service = AppUpdateDownloadService(
        storageService: AppUpdateStorageService(
          updateDirectoryResolver: () async => tempDirectory,
        ),
        chunkTimeout: const Duration(milliseconds: 80),
      );
      final asset = AppUpdateAsset(
        platform: 'windows',
        arch: 'x86_64',
        format: 'zip',
        primary: true,
        fileName: 'landa-v0.2.4-windows-x64.zip',
        size: payload.length,
        sha256: sha256.convert(payload).toString(),
        downloadUrl:
            'http://${server.address.address}:${server.port}/landa-v0.2.4-windows-x64.zip',
      );

      await expectLater(
        () => service.downloadAsset(asset),
        throwsA(isA<TimeoutException>()),
      );

      final targetPath = p.join(tempDirectory.path, asset.fileName);
      expect(await File(targetPath).exists(), isFalse);
      expect(await File('$targetPath.part').exists(), isFalse);

      final retriedFile = await service.downloadAsset(asset);
      expect(await retriedFile.exists(), isTrue);
      expect(await retriedFile.readAsBytes(), payload);
    },
  );
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

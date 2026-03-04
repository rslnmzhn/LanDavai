import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';

void main() {
  late VideoLinkShareService service;
  late HttpClient client;
  late Directory tempDir;

  setUp(() async {
    service = VideoLinkShareService();
    client = HttpClient();
    tempDir = await Directory.systemTemp.createTemp('landa_video_share_test_');
  });

  tearDown(() async {
    await service.stop();
    client.close(force: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('requires password and streams range after auth', () async {
    final file = File('${tempDir.path}\\sample.mp4');
    final bytes = List<int>.generate(200, (index) => index);
    await file.writeAsBytes(bytes, flush: true);

    final session = await service.publish(
      filePath: file.path,
      displayName: 'sample.mp4',
      password: 'secret-pass',
      port: 0,
    );
    final base = Uri.parse('http://127.0.0.1:${session.port}');

    final watchRequest = await client.getUrl(base.replace(path: '/watch'));
    final watchResponse = await watchRequest.close();
    final watchBody = utf8.decode(await _readAllBytes(watchResponse));
    expect(watchResponse.statusCode, HttpStatus.ok);
    expect(watchBody, contains('Enter password'));

    final unauthRequest = await client.getUrl(base.replace(path: '/stream'));
    final unauthResponse = await unauthRequest.close();
    expect(unauthResponse.statusCode, HttpStatus.unauthorized);

    final authRequest = await client.postUrl(base.replace(path: '/auth'));
    authRequest.followRedirects = false;
    authRequest.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    authRequest.write('password=secret-pass');
    final authResponse = await authRequest.close();
    expect(authResponse.statusCode, HttpStatus.found);
    final authCookie = authResponse.cookies.firstWhere(
      (cookie) => cookie.name == 'landa_video_token',
    );

    final streamRequest = await client.getUrl(base.replace(path: '/stream'));
    streamRequest.cookies.add(Cookie(authCookie.name, authCookie.value));
    streamRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=10-19');
    final streamResponse = await streamRequest.close();
    final streamed = await _readAllBytes(streamResponse);
    expect(streamResponse.statusCode, HttpStatus.partialContent);
    expect(
      streamResponse.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 10-19/200',
    );
    expect(streamed, bytes.sublist(10, 20));
  });

  test(
    'publishing a new file keeps same link and replaces old content',
    () async {
      final first = File('${tempDir.path}\\first.mp4');
      final second = File('${tempDir.path}\\second.mp4');
      await first.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      await second.writeAsBytes(<int>[9, 8, 7], flush: true);

      final firstSession = await service.publish(
        filePath: first.path,
        displayName: 'first.mp4',
        password: 'pass1',
        port: 0,
      );
      final secondSession = await service.publish(
        filePath: second.path,
        displayName: 'second.mp4',
        password: 'pass2',
        port: firstSession.port,
      );

      expect(secondSession.port, firstSession.port);
      expect(
        secondSession.buildWatchUrl(hostAddress: '127.0.0.1'),
        firstSession.buildWatchUrl(hostAddress: '127.0.0.1'),
      );

      final base = Uri.parse('http://127.0.0.1:${secondSession.port}');
      final authRequest = await client.postUrl(base.replace(path: '/auth'));
      authRequest.followRedirects = false;
      authRequest.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      authRequest.write('password=pass2');
      final authResponse = await authRequest.close();
      expect(authResponse.statusCode, HttpStatus.found);
      final authCookie = authResponse.cookies.firstWhere(
        (cookie) => cookie.name == 'landa_video_token',
      );

      final streamRequest = await client.getUrl(base.replace(path: '/stream'));
      streamRequest.cookies.add(Cookie(authCookie.name, authCookie.value));
      final streamResponse = await streamRequest.close();
      final streamBody = await _readAllBytes(streamResponse);
      expect(streamResponse.statusCode, HttpStatus.ok);
      expect(streamBody, <int>[9, 8, 7]);
    },
  );
}

Future<List<int>> _readAllBytes(HttpClientResponse response) async {
  final data = <int>[];
  await for (final chunk in response) {
    data.addAll(chunk);
  }
  return data;
}

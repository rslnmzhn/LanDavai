import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class VideoLinkShareSession {
  const VideoLinkShareSession({
    required this.port,
    required this.watchPath,
    required this.filePath,
    required this.fileName,
    required this.updatedAt,
  });

  final int port;
  final String watchPath;
  final String filePath;
  final String fileName;
  final DateTime updatedAt;

  String buildWatchUrl({required String hostAddress}) {
    return 'http://$hostAddress:$port$watchPath';
  }
}

class VideoLinkShareService {
  static const int defaultPort = 40444;
  static const String watchPath = '/watch';
  static const String _authPath = '/auth';
  static const String _streamPath = '/stream';
  static const String _authCookieName = 'landa_video_token';
  static const int maxAuthBodyBytes = 8 * 1024;
  static const int maxFailedAuthAttempts = 5;
  static const Duration authLockoutDuration = Duration(seconds: 30);

  HttpServer? _server;
  _ActiveVideoShare? _activeShare;
  final Map<String, _AuthAttemptWindow> _failedAuthByIp =
      <String, _AuthAttemptWindow>{};

  VideoLinkShareSession? get activeSession => _activeShare?.session;

  Future<VideoLinkShareSession> publish({
    required String filePath,
    required String displayName,
    required String password,
    int port = defaultPort,
  }) async {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) {
      throw ArgumentError('filePath must not be empty.');
    }
    final normalizedPassword = password.trim();
    if (normalizedPassword.isEmpty) {
      throw ArgumentError('password must not be empty.');
    }
    if (port < 0 || port > 65535) {
      throw ArgumentError('port must be between 0 and 65535.');
    }

    if (await FileSystemEntity.type(normalizedPath, followLinks: false) !=
        FileSystemEntityType.file) {
      throw ArgumentError('Path is not a regular file: $normalizedPath');
    }
    final file = File(normalizedPath);
    if (!await file.exists()) {
      throw ArgumentError('File does not exist: $normalizedPath');
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('Path is not a file: $normalizedPath');
    }

    await _ensureServer(port: port);
    final startedServer = _server;
    if (startedServer == null) {
      throw StateError('Video link server is not available.');
    }

    final normalizedDisplayName = displayName.trim().isEmpty
        ? p.basename(normalizedPath)
        : displayName.trim();
    final session = VideoLinkShareSession(
      port: startedServer.port,
      watchPath: watchPath,
      filePath: normalizedPath,
      fileName: normalizedDisplayName,
      updatedAt: DateTime.now(),
    );
    final salt = _buildRandomHex(16);
    _failedAuthByIp.clear();
    _activeShare = _ActiveVideoShare(
      session: session,
      contentType: _videoContentType(normalizedPath),
      passwordSalt: salt,
      passwordHash: _hashPassword(normalizedPassword, salt: salt),
      authToken: _buildRandomHex(32),
    );
    return session;
  }

  Future<void> stop() async {
    _activeShare = null;
    _failedAuthByIp.clear();
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _ensureServer({required int port}) async {
    final running = _server;
    if (running != null && (port == 0 || running.port == port)) {
      return;
    }
    if (running != null) {
      await running.close(force: true);
      _server = null;
    }

    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    server.listen(_handleRequest);
    _server = server;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final activeShare = _activeShare;
    if (activeShare == null) {
      await _writePlainResponse(
        request.response,
        statusCode: HttpStatus.notFound,
        body: 'No active shared video.',
      );
      return;
    }

    final path = request.uri.path;
    try {
      if (path == '/' || path == watchPath) {
        await _handleWatchPage(request, activeShare);
        return;
      }
      if (path == _authPath) {
        await _handleAuth(request, activeShare);
        return;
      }
      if (path == _streamPath) {
        await _handleVideoStream(request, activeShare);
        return;
      }
      await _writePlainResponse(
        request.response,
        statusCode: HttpStatus.notFound,
        body: 'Not found.',
      );
    } catch (_) {
      try {
        await _writePlainResponse(
          request.response,
          statusCode: HttpStatus.internalServerError,
          body: 'Failed to process request.',
        );
      } catch (_) {
        await request.response.close();
      }
    }
  }

  Future<void> _handleWatchPage(
    HttpRequest request,
    _ActiveVideoShare activeShare,
  ) async {
    final response = request.response;
    response.headers.contentType = ContentType.html;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(
      _buildWatchPageHtml(
        activeShare: activeShare,
        authorized: _isAuthorized(request, activeShare),
        error: request.uri.queryParameters['error'],
      ),
    );
    await response.close();
  }

  Future<void> _handleAuth(
    HttpRequest request,
    _ActiveVideoShare activeShare,
  ) async {
    if (request.method.toUpperCase() != 'POST') {
      await _writePlainResponse(
        request.response,
        statusCode: HttpStatus.methodNotAllowed,
        body: 'Method not allowed.',
      );
      return;
    }

    final remoteIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final now = DateTime.now();
    final attemptWindow = _failedAuthByIp[remoteIp];
    if (attemptWindow != null && attemptWindow.isLockedAt(now)) {
      await _writePlainResponse(
        request.response,
        statusCode: HttpStatus.tooManyRequests,
        body: 'Too many failed password attempts. Please wait and try again.',
      );
      return;
    }

    Map<String, String> fields;
    try {
      fields = await _readFormFields(request);
    } on _PayloadTooLargeException {
      await _writePlainResponse(
        request.response,
        statusCode: HttpStatus.requestEntityTooLarge,
        body: 'Request payload is too large.',
      );
      return;
    }

    final password = fields['password'] ?? '';
    final candidateHash = _hashPassword(password, salt: activeShare.passwordSalt);
    if (!_constantTimeEquals(candidateHash, activeShare.passwordHash)) {
      final updatedWindow = (attemptWindow ?? _AuthAttemptWindow()).recordFailure(
        now,
        maxFailures: maxFailedAuthAttempts,
        lockoutDuration: authLockoutDuration,
      );
      _failedAuthByIp[remoteIp] = updatedWindow;
      request.response.cookies.add(
        Cookie(_authCookieName, '')
          ..httpOnly = true
          ..sameSite = SameSite.lax
          ..path = '/'
          ..expires = DateTime.fromMillisecondsSinceEpoch(0),
      );
      await request.response.redirect(
        Uri(path: watchPath, queryParameters: <String, String>{'error': 'bad'}),
        status: HttpStatus.found,
      );
      return;
    }

    _failedAuthByIp.remove(remoteIp);
    request.response.cookies.add(
      Cookie(_authCookieName, activeShare.authToken)
        ..httpOnly = true
        ..sameSite = SameSite.lax
        ..path = '/',
    );
    await request.response.redirect(
      Uri(path: watchPath, queryParameters: <String, String>{'ok': '1'}),
      status: HttpStatus.found,
    );
  }

  Future<void> _handleVideoStream(
    HttpRequest request,
    _ActiveVideoShare activeShare,
  ) async {
    final method = request.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') {
      await _writePlainResponse(
        request.response,
        statusCode: HttpStatus.methodNotAllowed,
        body: 'Method not allowed.',
      );
      return;
    }
    if (!_isAuthorized(request, activeShare)) {
      await _writePlainResponse(
        request.response,
        statusCode: HttpStatus.unauthorized,
        body: 'Password required.',
      );
      return;
    }

    if (await FileSystemEntity.type(
          activeShare.session.filePath,
          followLinks: false,
        ) !=
        FileSystemEntityType.file) {
      await _writePlainResponse(
        request.response,
        statusCode: HttpStatus.notFound,
        body: 'Shared file is unavailable.',
      );
      return;
    }
    final file = File(activeShare.session.filePath);
    if (!await file.exists()) {
      await _writePlainResponse(
        request.response,
        statusCode: HttpStatus.notFound,
        body: 'Shared file is unavailable.',
      );
      return;
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      await _writePlainResponse(
        request.response,
        statusCode: HttpStatus.notFound,
        body: 'Shared file is unavailable.',
      );
      return;
    }

    final totalSize = stat.size;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    _ByteRange? range;
    if (rangeHeader != null && rangeHeader.trim().isNotEmpty) {
      try {
        range = _parseByteRange(rangeHeader, totalSize);
      } on FormatException {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$totalSize',
        );
        await request.response.close();
        return;
      }
    }

    final response = request.response;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      activeShare.contentType,
    );
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    int start = 0;
    int end = totalSize - 1;
    if (range != null) {
      start = range.start;
      end = range.end;
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$totalSize',
      );
      response.contentLength = (end - start) + 1;
    } else {
      response.statusCode = HttpStatus.ok;
      response.contentLength = totalSize;
    }

    if (method == 'HEAD') {
      await response.close();
      return;
    }

    await response.addStream(file.openRead(start, end + 1));
    await response.close();
  }

  bool _isAuthorized(HttpRequest request, _ActiveVideoShare activeShare) {
    for (final cookie in request.cookies) {
      if (cookie.name == _authCookieName &&
          _constantTimeEquals(cookie.value, activeShare.authToken)) {
        return true;
      }
    }
    return false;
  }

  Future<Map<String, String>> _readFormFields(HttpRequest request) async {
    if (request.contentLength > maxAuthBodyBytes) {
      throw const _PayloadTooLargeException();
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      if (builder.length + chunk.length > maxAuthBodyBytes) {
        throw const _PayloadTooLargeException();
      }
      builder.add(chunk);
    }
    final body = utf8.decode(builder.takeBytes(), allowMalformed: true);
    if (body.trim().isEmpty) {
      return const <String, String>{};
    }
    return Uri.splitQueryString(body);
  }

  _ByteRange _parseByteRange(String header, int totalSize) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) {
      throw const FormatException('Invalid range.');
    }

    final startRaw = match.group(1) ?? '';
    final endRaw = match.group(2) ?? '';
    if (startRaw.isEmpty && endRaw.isEmpty) {
      throw const FormatException('Invalid range.');
    }

    if (startRaw.isEmpty) {
      final suffixLength = int.tryParse(endRaw);
      if (suffixLength == null || suffixLength <= 0) {
        throw const FormatException('Invalid suffix range.');
      }
      final start = max(totalSize - suffixLength, 0);
      final end = totalSize - 1;
      if (start > end) {
        throw const FormatException('Invalid suffix range.');
      }
      return _ByteRange(start: start, end: end);
    }

    final start = int.tryParse(startRaw);
    var end = endRaw.isEmpty ? totalSize - 1 : int.tryParse(endRaw);
    if (start == null || end == null || start < 0) {
      throw const FormatException('Invalid range values.');
    }
    if (start >= totalSize) {
      throw const FormatException('Start is out of range.');
    }
    if (end >= totalSize) {
      end = totalSize - 1;
    }
    if (end < start) {
      throw const FormatException('End is out of range.');
    }
    return _ByteRange(start: start, end: end);
  }

  String _buildWatchPageHtml({
    required _ActiveVideoShare activeShare,
    required bool authorized,
    String? error,
  }) {
    final fileName = _escapeHtml(activeShare.session.fileName);
    final statusBlock = error == 'bad'
        ? '<p class="error">Wrong password. Try again.</p>'
        : authorized
        ? '<p class="ok">Access granted.</p>'
        : '<p class="hint">Enter password to watch the video.</p>';

    final authBlock = authorized
        ? '<p class="hint">Link is protected. You are authenticated for this browser.</p>'
        : '''
<form method="POST" action="$_authPath">
  <label for="password">Password</label>
  <input id="password" name="password" type="password" autocomplete="current-password" required />
  <button type="submit">Open video</button>
</form>
''';
    final playerBlock = authorized
        ? '''
<video controls autoplay preload="metadata">
  <source src="$_streamPath" type="${activeShare.contentType}" />
</video>
<p class="meta">Now playing: $fileName</p>
'''
        : '';

    return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Landa Video Link</title>
  <style>
    body { margin: 0; padding: 24px; background: #F6F5FF; color: #1F1F2E; font-family: Manrope, sans-serif; }
    .wrap { max-width: 860px; margin: 0 auto; background: #FFFFFF; border-radius: 16px; padding: 20px; box-sizing: border-box; }
    h1 { margin: 0 0 8px; font-size: 24px; }
    p { margin: 8px 0; }
    .hint { color: #5B5B73; }
    .error { color: #C06C84; }
    .ok { color: #4CAF93; }
    label { display: block; margin: 12px 0 6px; color: #5B5B73; }
    input { width: 100%; padding: 10px 12px; border: 1px solid #DCD7FF; border-radius: 12px; box-sizing: border-box; font: inherit; }
    button { margin-top: 12px; background: #8B7CF6; color: #FFFFFF; border: 0; border-radius: 12px; height: 44px; padding: 0 16px; cursor: pointer; font: inherit; }
    video { margin-top: 14px; width: 100%; max-height: 72vh; background: #000000; border-radius: 12px; }
    .meta { font-size: 13px; color: #8C8CA1; }
  </style>
</head>
<body>
  <main class="wrap">
    <h1>Landa Video Link</h1>
    <p class="hint">File: $fileName</p>
    $statusBlock
    $authBlock
    $playerBlock
  </main>
</body>
</html>
''';
  }

  String _videoContentType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.mp4':
      case '.m4v':
        return 'video/mp4';
      case '.webm':
        return 'video/webm';
      case '.mkv':
        return 'video/x-matroska';
      case '.avi':
        return 'video/x-msvideo';
      case '.mov':
        return 'video/quicktime';
      case '.3gp':
        return 'video/3gpp';
      case '.mpeg':
      case '.mpg':
        return 'video/mpeg';
      default:
        return 'application/octet-stream';
    }
  }

  String _hashPassword(String value, {required String salt}) {
    return sha256.convert(utf8.encode('$salt:$value')).toString();
  }

  String _buildRandomHex(int byteCount) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < aBytes.length; i++) {
      diff |= aBytes[i] ^ bBytes[i];
    }
    return diff == 0;
  }

  String _escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  Future<void> _writePlainResponse(
    HttpResponse response, {
    required int statusCode,
    required String body,
  }) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.text;
    response.write(body);
    await response.close();
  }
}

class _ActiveVideoShare {
  const _ActiveVideoShare({
    required this.session,
    required this.contentType,
    required this.passwordSalt,
    required this.passwordHash,
    required this.authToken,
  });

  final VideoLinkShareSession session;
  final String contentType;
  final String passwordSalt;
  final String passwordHash;
  final String authToken;
}

class _PayloadTooLargeException implements Exception {
  const _PayloadTooLargeException();
}

class _AuthAttemptWindow {
  const _AuthAttemptWindow({this.failures = 0, this.lockedUntil});

  final int failures;
  final DateTime? lockedUntil;

  bool isLockedAt(DateTime now) =>
      lockedUntil != null && now.isBefore(lockedUntil!);

  _AuthAttemptWindow recordFailure(
    DateTime now, {
    required int maxFailures,
    required Duration lockoutDuration,
  }) {
    final activeFailures = lockedUntil != null && !now.isBefore(lockedUntil!)
        ? 0
        : failures;
    final nextFailures = activeFailures + 1;
    if (nextFailures >= maxFailures) {
      return _AuthAttemptWindow(
        failures: nextFailures,
        lockedUntil: now.add(lockoutDuration),
      );
    }
    return _AuthAttemptWindow(failures: nextFailures);
  }
}

class _ByteRange {
  const _ByteRange({required this.start, required this.end});

  final int start;
  final int end;
}

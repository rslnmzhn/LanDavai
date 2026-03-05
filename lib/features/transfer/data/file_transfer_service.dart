import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/transfer_request.dart';

class TransferSourceFile {
  TransferSourceFile({
    required this.sourcePath,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    this.deleteAfterTransfer = false,
  });

  final String sourcePath;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final bool deleteAfterTransfer;
}

class TransferReceiveSession {
  TransferReceiveSession({
    required this.port,
    required this.result,
    required this.close,
  });

  final int port;
  final Future<FileTransferResult> result;
  final Future<void> Function() close;
}

class FileTransferResult {
  FileTransferResult({
    required this.success,
    required this.message,
    required this.savedPaths,
    required this.totalBytes,
    required this.destinationDirectory,
    required this.hashVerified,
  });

  final bool success;
  final String message;
  final List<String> savedPaths;
  final int totalBytes;
  final String destinationDirectory;
  final bool hashVerified;
}

class FileTransferService {
  static const int _headerLengthBytes = 4;
  static const int _maxHeaderBytes = 1024 * 1024;
  static const int _chunkBytes = 64 * 1024;

  Future<TransferReceiveSession> startReceiver({
    required String requestId,
    required List<TransferFileManifestItem> expectedItems,
    required Directory destinationDirectory,
    Duration timeout = const Duration(minutes: 3),
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final resultCompleter = Completer<FileTransferResult>();
    var closed = false;

    Future<void> closeSession() async {
      if (closed) {
        return;
      }
      closed = true;
      server.close();
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(
          FileTransferResult(
            success: false,
            message: 'Transfer receiver closed.',
            savedPaths: <String>[],
            totalBytes: 0,
            destinationDirectory: destinationDirectory.path,
            hashVerified: false,
          ),
        );
      }
    }

    Timer? timeoutTimer;
    timeoutTimer = Timer(timeout, () {
      if (closed) {
        return;
      }
      unawaited(closeSession());
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(
          FileTransferResult(
            success: false,
            message: 'Transfer receive timed out.',
            savedPaths: <String>[],
            totalBytes: 0,
            destinationDirectory: destinationDirectory.path,
            hashVerified: false,
          ),
        );
      }
    });

    server.listen(
      (socket) {
        if (closed) {
          socket.destroy();
          return;
        }
        closed = true;
        timeoutTimer?.cancel();
        server.close();
        unawaited(
          _receiveFiles(
            socket: socket,
            requestId: requestId,
            expectedItems: expectedItems,
            destinationDirectory: destinationDirectory,
            onProgress: onProgress,
          ).then(resultCompleter.complete).catchError((Object error) {
            if (!resultCompleter.isCompleted) {
              resultCompleter.complete(
                FileTransferResult(
                  success: false,
                  message: 'Transfer receive failed: $error',
                  savedPaths: <String>[],
                  totalBytes: 0,
                  destinationDirectory: destinationDirectory.path,
                  hashVerified: false,
                ),
              );
            }
          }),
        );
      },
      onError: (Object error) {
        timeoutTimer?.cancel();
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(
            FileTransferResult(
              success: false,
              message: 'Receiver socket error: $error',
              savedPaths: <String>[],
              totalBytes: 0,
              destinationDirectory: destinationDirectory.path,
              hashVerified: false,
            ),
          );
        }
      },
    );

    resultCompleter.future.whenComplete(() {
      timeoutTimer?.cancel();
      server.close();
    });

    return TransferReceiveSession(
      port: server.port,
      result: resultCompleter.future,
      close: closeSession,
    );
  }

  Future<void> sendFiles({
    required String host,
    required int port,
    required String requestId,
    required List<TransferSourceFile> files,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
    );
    try {
      final payload = <String, Object?>{
        'requestId': requestId,
        'files': files
            .map(
              (file) => <String, Object>{
                'name': file.fileName,
                'size': file.sizeBytes,
                'sha256': file.sha256,
              },
            )
            .toList(growable: false),
      };
      final headerBytes = utf8.encode(jsonEncode(payload));
      if (headerBytes.length > _maxHeaderBytes) {
        throw StateError('Transfer header is too large.');
      }

      final headerLength = ByteData(_headerLengthBytes)
        ..setUint32(0, headerBytes.length, Endian.big);
      socket.add(headerLength.buffer.asUint8List());
      socket.add(headerBytes);
      await socket.flush();

      final totalBytes = files.fold<int>(
        0,
        (sum, file) => sum + file.sizeBytes,
      );
      var sentBytes = 0;
      onProgress?.call(0, totalBytes);
      for (final file in files) {
        final source = File(file.sourcePath);
        if (!await source.exists()) {
          throw StateError('Source file does not exist: ${file.sourcePath}');
        }

        final digestSink = _DigestSink();
        final hashSink = sha256.startChunkedConversion(digestSink);
        await for (final chunk in source.openRead()) {
          socket.add(chunk);
          hashSink.add(chunk);
          sentBytes += chunk.length;
          onProgress?.call(sentBytes, totalBytes);
        }
        hashSink.close();

        final actualSha = digestSink.value?.toString() ?? '';
        if (actualSha.toLowerCase() != file.sha256.toLowerCase()) {
          throw StateError(
            'Sender SHA-256 mismatch for ${file.fileName}. '
            'File changed during transfer preparation.',
          );
        }
      }
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  Future<FileTransferResult> _receiveFiles({
    required Socket socket,
    required String requestId,
    required List<TransferFileManifestItem> expectedItems,
    required Directory destinationDirectory,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final reader = _SocketReader(socket);
    await destinationDirectory.create(recursive: true);

    final headerLengthBytes = await reader.readExact(_headerLengthBytes);
    final headerLength = ByteData.sublistView(
      headerLengthBytes,
    ).getUint32(0, Endian.big);
    if (headerLength <= 0 || headerLength > _maxHeaderBytes) {
      throw StateError('Invalid transfer header length: $headerLength');
    }

    final headerBytes = await reader.readExact(headerLength);
    final decoded = jsonDecode(utf8.decode(headerBytes));
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid transfer header payload.');
    }

    final headerRequestId = decoded['requestId'] as String?;
    final headerFiles = decoded['files'];
    if (headerRequestId == null || headerFiles is! List<dynamic>) {
      throw StateError('Transfer header is missing required fields.');
    }
    if (headerRequestId != requestId) {
      throw StateError('Transfer request mismatch.');
    }

    final normalizedExpected = expectedItems
        .map(
          (item) => _FileDescriptor(
            name: item.fileName,
            sizeBytes: item.sizeBytes,
            sha256: item.sha256,
          ),
        )
        .toList(growable: false);
    final normalizedActual = headerFiles
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => _FileDescriptor(
            name: item['name'] as String,
            sizeBytes: (item['size'] as num).toInt(),
            sha256: item['sha256'] as String,
          ),
        )
        .toList(growable: false);

    final expectedByName = <String, _FileDescriptor>{
      for (final expected in normalizedExpected) expected.name: expected,
    };
    final seenActualNames = <String>{};
    for (final actual in normalizedActual) {
      if (!seenActualNames.add(actual.name)) {
        throw StateError('Transfer manifest duplicate file: ${actual.name}.');
      }
      final expected = expectedByName[actual.name];
      if (expected == null ||
          expected.sizeBytes != actual.sizeBytes ||
          expected.sha256.toLowerCase() != actual.sha256.toLowerCase()) {
        throw StateError('Transfer manifest mismatch for ${actual.name}.');
      }
    }

    final savedPaths = <String>[];
    var totalBytes = 0;
    final expectedTotalBytes = normalizedActual.fold<int>(
      0,
      (sum, file) => sum + file.sizeBytes,
    );
    onProgress?.call(0, expectedTotalBytes);

    String? inProgressPath;
    try {
      for (final file in normalizedActual) {
        final destinationPath = await _allocateDestinationPath(
          destinationDirectory: destinationDirectory,
          relativePath: file.name,
        );
        inProgressPath = destinationPath;
        final destinationFile = File(destinationPath);
        await destinationFile.parent.create(recursive: true);
        final sink = destinationFile.openWrite(mode: FileMode.writeOnly);

        final digestSink = _DigestSink();
        final hashSink = sha256.startChunkedConversion(digestSink);
        var remaining = file.sizeBytes;
        while (remaining > 0) {
          final toRead = min(remaining, _chunkBytes);
          final chunk = await reader.readExact(toRead);
          sink.add(chunk);
          hashSink.add(chunk);
          remaining -= chunk.length;
          totalBytes += chunk.length;
          onProgress?.call(totalBytes, expectedTotalBytes);
        }

        hashSink.close();
        await sink.flush();
        await sink.close();

        final actualSha = digestSink.value?.toString() ?? '';
        if (actualSha.toLowerCase() != file.sha256.toLowerCase()) {
          try {
            await destinationFile.delete();
          } catch (_) {}
          throw StateError('SHA-256 mismatch for ${file.name}');
        }
        savedPaths.add(destinationPath);
        inProgressPath = null;
      }

      return FileTransferResult(
        success: true,
        message: 'Transfer completed. Hash verified.',
        savedPaths: savedPaths,
        totalBytes: totalBytes,
        destinationDirectory: destinationDirectory.path,
        hashVerified: true,
      );
    } on Object {
      await _cleanupFailedTransferFiles(savedPaths);
      if (inProgressPath != null) {
        try {
          await File(inProgressPath).delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      await reader.close();
      await socket.close();
    }
  }

  Future<void> _cleanupFailedTransferFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<String> _allocateDestinationPath({
    required Directory destinationDirectory,
    required String relativePath,
  }) async {
    final sanitized = _sanitizeRelativePath(relativePath);
    final fullPath = p.join(destinationDirectory.path, sanitized);
    final file = File(fullPath);
    if (!await file.exists()) {
      return fullPath;
    }

    final dir = p.dirname(fullPath);
    final name = p.basenameWithoutExtension(fullPath);
    final ext = p.extension(fullPath);
    var counter = 1;
    while (true) {
      final candidate = p.join(dir, '$name ($counter)$ext');
      if (!await File(candidate).exists()) {
        return candidate;
      }
      counter += 1;
    }
  }

  String _sanitizeRelativePath(String input) {
    final raw = input.replaceAll('\\', '/');
    final parts = raw
        .split('/')
        .map((part) => _sanitizeRelativePathPart(part.trim()))
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'file.bin';
    }
    return p.joinAll(parts);
  }

  String _sanitizeRelativePathPart(String input) {
    if (input.isEmpty) {
      return '';
    }

    // Remove control chars and separators that may be accepted on Unix
    // but are invalid file name chars on Windows.
    var value = input
        .replaceAll(RegExp(r'[\x00-\x1F]'), '')
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    if (Platform.isWindows) {
      value = value.trimRight();
      value = value.replaceFirst(RegExp(r'[. ]+$'), '');
      if (value.isEmpty) {
        return '_';
      }

      final reserved = <String>{
        'con',
        'prn',
        'aux',
        'nul',
        'com1',
        'com2',
        'com3',
        'com4',
        'com5',
        'com6',
        'com7',
        'com8',
        'com9',
        'lpt1',
        'lpt2',
        'lpt3',
        'lpt4',
        'lpt5',
        'lpt6',
        'lpt7',
        'lpt8',
        'lpt9',
      };
      final base = value.split('.').first.toLowerCase();
      if (reserved.contains(base)) {
        value = '_$value';
      }
    }

    // Prevent very long path segments.
    if (value.length > 120) {
      value = value.substring(0, 120);
    }

    return value.isEmpty ? '_' : value;
  }
}

class _FileDescriptor {
  const _FileDescriptor({
    required this.name,
    required this.sizeBytes,
    required this.sha256,
  });

  final String name;
  final int sizeBytes;
  final String sha256;
}

class _SocketReader {
  _SocketReader(Socket socket) {
    _subscription = socket.listen(
      (chunk) {
        if (chunk.isEmpty) {
          return;
        }
        _chunks.addLast(Uint8List.fromList(chunk));
        _availableBytes += chunk.length;
        _signalWaiter();
      },
      onError: (Object error) {
        _error = error;
        _signalWaiter();
      },
      onDone: () {
        _isDone = true;
        _signalWaiter();
      },
      cancelOnError: true,
    );
  }

  final Queue<Uint8List> _chunks = Queue<Uint8List>();
  late final StreamSubscription<List<int>> _subscription;
  Completer<void>? _waiter;
  Object? _error;
  var _isDone = false;
  var _availableBytes = 0;
  var _headOffset = 0;

  Future<Uint8List> readExact(int byteCount) async {
    if (byteCount < 0) {
      throw ArgumentError.value(byteCount, 'byteCount', 'Must be >= 0');
    }
    if (byteCount == 0) {
      return Uint8List(0);
    }

    while (_availableBytes < byteCount) {
      if (_error != null) {
        throw StateError('Socket read failed: $_error');
      }
      if (_isDone) {
        throw StateError(
          'Socket closed before reading $byteCount bytes '
          '(available=$_availableBytes).',
        );
      }
      _waiter ??= Completer<void>();
      await _waiter!.future;
    }

    final out = Uint8List(byteCount);
    var written = 0;
    while (written < byteCount) {
      final head = _chunks.first;
      final remainingInHead = head.length - _headOffset;
      final toCopy = min(byteCount - written, remainingInHead);
      out.setRange(written, written + toCopy, head, _headOffset);
      written += toCopy;
      _headOffset += toCopy;
      _availableBytes -= toCopy;

      if (_headOffset >= head.length) {
        _chunks.removeFirst();
        _headOffset = 0;
      }
    }
    return out;
  }

  void _signalWaiter() {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
    _waiter = null;
  }

  Future<void> close() => _subscription.cancel();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

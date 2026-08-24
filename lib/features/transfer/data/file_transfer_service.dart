import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/transfer_request.dart';
import 'socket_exact_reader.dart';
import 'transfer_destination_path_allocator.dart';
import 'transfer_failed_file_cleanup.dart';
import 'transfer_file_integrity.dart';
import 'transfer_header_codec.dart';

typedef TransferRuntimeDiagnosticCallback =
    void Function({
      required String stage,
      Map<String, Object?> details,
      Object? error,
      StackTrace? stackTrace,
    });

typedef TransferStreamedFileHashCallback =
    void Function({
      required TransferSourceFile file,
      required String computedSha256,
    });

class TransferSourceBatch {
  const TransferSourceBatch({
    required this.batchNumber,
    required this.startIndex,
    required this.files,
  });

  final int batchNumber;
  final int startIndex;
  final List<TransferSourceFile> files;
}

class TransferSourceFile {
  TransferSourceFile({
    required this.sourcePath,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    this.modifiedAtMs,
    this.deleteAfterTransfer = false,
  });

  final String sourcePath;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final int? modifiedAtMs;
  final bool deleteAfterTransfer;
}

class TransferReceiveSession {
  TransferReceiveSession({
    required this.port,
    required this.result,
    required this.armTimeout,
    required this.close,
  });

  final int port;
  final Future<FileTransferResult> result;
  final void Function() armTimeout;
  final Future<void> Function() close;
}

class FileTransferResult {
  const FileTransferResult({
    required this.success,
    required this.message,
    required this.savedPaths,
    required this.receivedItems,
    required this.totalBytes,
    required this.destinationDirectory,
    required this.hashVerified,
  });

  final bool success;
  final String message;
  final List<String> savedPaths;
  final List<TransferFileManifestItem> receivedItems;
  final int totalBytes;
  final String destinationDirectory;
  final bool hashVerified;
}

class FileTransferService {
  static const int _headerLengthBytes = 4;
  static const int _maxHeaderBytes = 8 * 1024 * 1024;
  static const int _chunkBytes = 64 * 1024;
  static const TransferHeaderCodec _transferHeaderCodec = TransferHeaderCodec();
  static const TransferDestinationPathAllocator _destinationPathAllocator =
      TransferDestinationPathAllocator();
  static const TransferFileIntegrity _fileIntegrity = TransferFileIntegrity();
  static const TransferFailedFileCleanup _failedFileCleanup =
      TransferFailedFileCleanup();

  /// Maximum time the receiver waits for the next bytes on an established
  /// connection before giving up. The timer is re-armed after every
  /// successful read, so slow-but-progressing transfers are never cut off.
  static const Duration receiveIdleTimeout = Duration(seconds: 30);

  Future<TransferReceiveSession> startReceiver({
    required String requestId,
    required List<TransferFileManifestItem>? expectedItems,
    required Directory destinationDirectory,
    Duration timeout = const Duration(minutes: 3),
    bool armTimeoutImmediately = true,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    String? destinationRelativeRootPrefix,
    Future<String> Function({
      required Directory destinationDirectory,
      required String relativePath,
    })?
    destinationPathAllocator,
    TransferRuntimeDiagnosticCallback? onDiagnosticEvent,
    Duration receiveIdleTimeoutOverride = Duration.zero,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final resultCompleter = Completer<FileTransferResult>();
    var closed = false;
    onDiagnosticEvent?.call(
      stage: 'receiver_started',
      details: <String, Object?>{
        'port': server.port,
        'destinationDirectory': destinationDirectory.path,
        'expectedItemCount': expectedItems?.length ?? -1,
        'destinationRelativeRootPrefix': destinationRelativeRootPrefix,
      },
    );

    Future<void> closeSession() async {
      if (closed) {
        return;
      }
      closed = true;
      server.close();
      onDiagnosticEvent?.call(
        stage: 'receiver_closed',
        details: <String, Object?>{
          'destinationDirectory': destinationDirectory.path,
        },
      );
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(
          FileTransferResult(
            success: false,
            message: 'Transfer receiver closed.',
            savedPaths: <String>[],
            receivedItems: <TransferFileManifestItem>[],
            totalBytes: 0,
            destinationDirectory: destinationDirectory.path,
            hashVerified: false,
          ),
        );
      }
    }

    Timer? timeoutTimer;
    var timeoutArmed = false;
    final effectiveIdleTimeout = receiveIdleTimeoutOverride > Duration.zero
        ? receiveIdleTimeoutOverride
        : receiveIdleTimeout;
    // Once a socket is accepted, the original timer becomes an idle watchdog:
    // it is re-armed after every successful read instead of being cancelled,
    // so a stalled sender can no longer park the receive session forever.
    var idleWatchdogActive = false;
    // Set together with [idleWatchdogActive] so the watchdog can destroy a
    // stalled connection; otherwise its result would wait on more reads.
    void Function()? socketDestroyCallback;

    void armTimeout() {
      if (closed || timeoutArmed) {
        return;
      }
      timeoutArmed = true;
      onDiagnosticEvent?.call(
        stage: 'receiver_timeout_armed',
        details: <String, Object?>{'timeoutSeconds': timeout.inSeconds},
      );
      timeoutTimer = Timer(timeout, () {
        if (closed || resultCompleter.isCompleted) {
          return;
        }
        onDiagnosticEvent?.call(
          stage: 'receiver_timeout',
          details: <String, Object?>{'timeoutSeconds': timeout.inSeconds},
        );
        // Complete before closing: closeSession would otherwise finish the
        // future with the generic "receiver closed" message first.
        resultCompleter.complete(
          FileTransferResult(
            success: false,
            message: 'Transfer receive timed out.',
            savedPaths: <String>[],
            receivedItems: <TransferFileManifestItem>[],
            totalBytes: 0,
            destinationDirectory: destinationDirectory.path,
            hashVerified: false,
          ),
        );
        unawaited(closeSession());
      });
    }

    void armIdleWatchdog() {
      // Deliberately not gated on `closed`: the connection handler reuses
      // that flag to mean "a socket was accepted", which is exactly when
      // this watchdog may run. Armed only while a socket read is actually
      // pending, so slow disk-bound phases without incoming bytes are not
      // mistaken for a stalled sender.
      if (!idleWatchdogActive || resultCompleter.isCompleted) {
        return;
      }
      timeoutTimer?.cancel();
      timeoutTimer = Timer(effectiveIdleTimeout, () {
        if (resultCompleter.isCompleted) {
          return;
        }
        onDiagnosticEvent?.call(
          stage: 'receiver_idle_timeout',
          details: <String, Object?>{
            'idleTimeoutSeconds': effectiveIdleTimeout.inSeconds,
          },
        );
        socketDestroyCallback?.call();
        // Complete before closing: closeSession would otherwise finish the
        // future with the generic "receiver closed" message first.
        resultCompleter.complete(
          FileTransferResult(
            success: false,
            message:
                'Transfer receive stalled: no data for '
                '${effectiveIdleTimeout.inSeconds}s.',
            savedPaths: <String>[],
            receivedItems: <TransferFileManifestItem>[],
            totalBytes: 0,
            destinationDirectory: destinationDirectory.path,
            hashVerified: false,
          ),
        );
        unawaited(closeSession());
      });
    }

    void disarmIdleWatchdog() {
      timeoutTimer?.cancel();
      timeoutTimer = null;
    }

    if (armTimeoutImmediately) {
      armTimeout();
    } else {
      onDiagnosticEvent?.call(
        stage: 'receiver_timeout_deferred',
        details: <String, Object?>{'timeoutSeconds': timeout.inSeconds},
      );
    }

    server.listen(
      (socket) {
        if (closed) {
          socket.destroy();
          return;
        }
        closed = true;
        server.close();
        // The pre-connection timeout is superseded by the per-read idle
        // watchdog for the lifetime of this connection.
        idleWatchdogActive = true;
        socketDestroyCallback = socket.destroy;
        onDiagnosticEvent?.call(
          stage: 'receiver_connected',
          details: <String, Object?>{
            'remoteAddress': socket.remoteAddress.address,
            'remotePort': socket.remotePort,
          },
        );
        unawaited(
          _receiveFiles(
                socket: socket,
                requestId: requestId,
                expectedItems: expectedItems,
                destinationDirectory: destinationDirectory,
                onProgress: onProgress,
                onDiagnosticEvent: onDiagnosticEvent,
                destinationRelativeRootPrefix: destinationRelativeRootPrefix,
                destinationPathAllocator: destinationPathAllocator,
                onBeforeSocketRead: armIdleWatchdog,
                onAfterSocketRead: disarmIdleWatchdog,
              )
              .then((result) {
                if (!resultCompleter.isCompleted) {
                  resultCompleter.complete(result);
                }
              })
              .catchError((Object error) {
                onDiagnosticEvent?.call(
                  stage: 'receiver_stream_failure',
                  error: error,
                );
                if (!resultCompleter.isCompleted) {
                  resultCompleter.complete(
                    FileTransferResult(
                      success: false,
                      message: 'Transfer receive failed: $error',
                      savedPaths: <String>[],
                      receivedItems: <TransferFileManifestItem>[],
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
        onDiagnosticEvent?.call(stage: 'receiver_socket_error', error: error);
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(
            FileTransferResult(
              success: false,
              message: 'Receiver socket error: $error',
              savedPaths: <String>[],
              receivedItems: <TransferFileManifestItem>[],
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
      armTimeout: armTimeout,
      close: closeSession,
    );
  }

  Future<void> sendFiles({
    required String host,
    required int port,
    required String requestId,
    required List<TransferSourceFile> files,
    List<TransferFileManifestItem>? manifestItems,
    Future<TransferSourceBatch> Function(int startIndex)? resolveBatch,
    Future<TransferSourceFile> Function(int index)? resolveFileAt,
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferRuntimeDiagnosticCallback? onDiagnosticEvent,
    TransferStreamedFileHashCallback? onFileHashed,
  }) async {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
    );
    TransferSourceFile? currentFile;
    try {
      final effectiveManifestItems =
          manifestItems ??
          files
              .map(
                (file) => TransferFileManifestItem(
                  fileName: file.fileName,
                  sizeBytes: file.sizeBytes,
                  sha256: file.sha256,
                ),
              )
              .toList(growable: false);
      final knownHashFileCount = effectiveManifestItems.where((file) {
        return file.sha256.trim().isNotEmpty;
      }).length;
      final missingHashFileCount =
          effectiveManifestItems.length - knownHashFileCount;
      onDiagnosticEvent?.call(
        stage: 'transfer_header_build_start',
        details: <String, Object?>{
          'fileCount': effectiveManifestItems.length,
          'preparedFileCount': files.length,
          'knownHashFileCount': knownHashFileCount,
          'missingHashFileCount': missingHashFileCount,
        },
      );
      final header = _transferHeaderCodec.encode(
        TransferHeader(requestId: requestId, files: effectiveManifestItems),
      );
      final headerBytes = header.bytes;
      onDiagnosticEvent?.call(
        stage: 'transfer_header_built',
        details: <String, Object?>{
          'fileCount': effectiveManifestItems.length,
          'preparedFileCount': files.length,
          'knownHashFileCount': knownHashFileCount,
          'missingHashFileCount': missingHashFileCount,
          'headerBytes': header.bytes.length,
          'rawHeaderBytes': header.rawBytesLength,
          'compressed': header.compressed,
        },
      );
      if (headerBytes.length > _maxHeaderBytes) {
        throw StateError('Transfer header is too large.');
      }

      final headerLength = ByteData(_headerLengthBytes)
        ..setUint32(0, headerBytes.length, Endian.big);
      onDiagnosticEvent?.call(
        stage: 'send_start',
        details: <String, Object?>{
          'host': host,
          'port': port,
          'fileCount': effectiveManifestItems.length,
          'preparedFileCount': files.length,
          'knownHashFileCount': knownHashFileCount,
          'missingHashFileCount': missingHashFileCount,
        },
      );
      socket.add(headerLength.buffer.asUint8List());
      socket.add(headerBytes);
      await socket.flush();

      final totalBytes = effectiveManifestItems.fold<int>(
        0,
        (sum, file) => sum + file.sizeBytes,
      );
      var activeBatchNumber = files.isNotEmpty ? 1 : 0;
      var activeBatchStartIndex = 0;
      var activeBatchFileCount = files.length;
      var activeBatchEndIndex = files.length;
      TransferSourceBatch? activeResolvedBatch;
      var sentBytes = 0;
      var firstByteSentLogged = false;
      onProgress?.call(0, totalBytes);
      for (var index = 0; index < effectiveManifestItems.length; index += 1) {
        final file = index < files.length
            ? files[index]
            : await (() async {
                if (resolveBatch != null) {
                  if (activeResolvedBatch == null ||
                      index < activeBatchStartIndex ||
                      index >= activeBatchEndIndex) {
                    activeResolvedBatch = await resolveBatch(index);
                    if (activeResolvedBatch!.startIndex != index) {
                      throw StateError(
                        'Transfer batch start mismatch for index $index.',
                      );
                    }
                    if (activeResolvedBatch!.files.isEmpty) {
                      throw StateError(
                        'Transfer batch resolver returned an empty batch.',
                      );
                    }
                    activeBatchNumber = activeResolvedBatch!.batchNumber;
                    activeBatchStartIndex = activeResolvedBatch!.startIndex;
                    activeBatchFileCount = activeResolvedBatch!.files.length;
                    activeBatchEndIndex =
                        activeBatchStartIndex + activeBatchFileCount;
                  }
                  return activeResolvedBatch!.files[index -
                      activeBatchStartIndex];
                }
                return resolveFileAt?.call(index) ??
                    Future<TransferSourceFile>.error(
                      StateError(
                        'Transfer source resolver missing for file index $index.',
                      ),
                    );
              })();
        currentFile = file;
        final source = File(file.sourcePath);
        if (!await source.exists()) {
          throw StateError('Source file does not exist: ${file.sourcePath}');
        }
        final actualSize = await source.length();
        if (actualSize != file.sizeBytes) {
          throw StateError(
            'Sender file size mismatch for ${file.fileName}. '
            'File changed during transfer preparation.',
          );
        }

        final digestSink = _DigestSink();
        final hashSink = sha256.startChunkedConversion(digestSink);
        await for (final chunk in source.openRead()) {
          socket.add(chunk);
          hashSink.add(chunk);
          sentBytes += chunk.length;
          if (!firstByteSentLogged && chunk.isNotEmpty) {
            firstByteSentLogged = true;
            onDiagnosticEvent?.call(
              stage: 'transfer_stream_first_byte_sent',
              details: <String, Object?>{
                'fileName': file.fileName,
                'sentBytes': sentBytes,
                'totalBytes': totalBytes,
              },
            );
          }
          onProgress?.call(sentBytes, totalBytes);
        }
        hashSink.close();

        final actualSha = digestSink.value?.toString() ?? '';
        final expectedSha = file.sha256.trim();
        if (expectedSha.isNotEmpty &&
            actualSha.toLowerCase() != expectedSha.toLowerCase()) {
          throw StateError(
            'Sender SHA-256 mismatch for ${file.fileName}. '
            'File changed during transfer preparation.',
          );
        }
        onFileHashed?.call(file: file, computedSha256: actualSha);
        final completedBatch =
            activeBatchFileCount > 0 && index + 1 == activeBatchEndIndex;
        if (completedBatch && resolveBatch != null) {
          onDiagnosticEvent?.call(
            stage: 'sender_whole_share_batch_sent',
            details: <String, Object?>{
              'batchNumber': activeBatchNumber,
              'batchFileCount': activeBatchFileCount,
              'batchStartIndex': activeBatchStartIndex,
              'cumulativeSentFileCount': index + 1,
              'totalManifestFileCount': effectiveManifestItems.length,
            },
          );
        }
      }
      await socket.flush();
      onDiagnosticEvent?.call(
        stage: 'send_complete',
        details: <String, Object?>{
          'host': host,
          'port': port,
          'fileCount': effectiveManifestItems.length,
          'preparedFileCount': files.length,
          'totalBytes': totalBytes,
        },
      );
    } catch (error, stackTrace) {
      onDiagnosticEvent?.call(
        stage: 'send_failure',
        details: <String, Object?>{
          'host': host,
          'port': port,
          'fileCount': manifestItems?.length ?? files.length,
          'preparedFileCount': files.length,
          if (currentFile != null) 'currentFileName': currentFile.fileName,
          if (currentFile != null) 'currentSourcePath': currentFile.sourcePath,
        },
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      await socket.close();
    }
  }

  Future<FileTransferResult> _receiveFiles({
    required Socket socket,
    required String requestId,
    required List<TransferFileManifestItem>? expectedItems,
    required Directory destinationDirectory,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    TransferRuntimeDiagnosticCallback? onDiagnosticEvent,
    String? destinationRelativeRootPrefix,
    Future<String> Function({
      required Directory destinationDirectory,
      required String relativePath,
    })?
    destinationPathAllocator,
    void Function()? onBeforeSocketRead,
    void Function()? onAfterSocketRead,
  }) async {
    final reader = SocketExactReader(socket);
    await destinationDirectory.create(recursive: true);

    // The idle watchdog is scoped to pending socket reads only: armed just
    // before each read and cancelled right after it completes. Disk-bound
    // phases between reads (path allocation, hashing of completed files)
    // produce no incoming bytes and must not be mistaken for a stalled
    // sender, while silence during an awaited read still trips the timer.

    onBeforeSocketRead?.call();
    final headerLengthBytes = await reader.readExact(_headerLengthBytes);
    onAfterSocketRead?.call();
    final headerLength = ByteData.sublistView(
      headerLengthBytes,
    ).getUint32(0, Endian.big);
    if (headerLength <= 0 || headerLength > _maxHeaderBytes) {
      throw StateError('Invalid transfer header length: $headerLength');
    }

    onBeforeSocketRead?.call();
    final headerBytes = await reader.readExact(headerLength);
    onAfterSocketRead?.call();
    final header = _transferHeaderCodec.decode(headerBytes);
    if (header.requestId != requestId) {
      throw StateError('Transfer request mismatch.');
    }

    final normalizedExpected =
        (expectedItems ?? const <TransferFileManifestItem>[])
            .map(
              (item) => _FileDescriptor(
                name: item.fileName,
                sizeBytes: item.sizeBytes,
                sha256: item.sha256,
              ),
            )
            .toList(growable: false);
    final normalizedActual = header.files
        .map(
          (item) => _FileDescriptor(
            name: item.fileName,
            sizeBytes: item.sizeBytes,
            sha256: item.sha256,
          ),
        )
        .toList(growable: false);

    if (normalizedExpected.isNotEmpty) {
      final expectedByName = <String, _FileDescriptor>{
        for (final expected in normalizedExpected) expected.name: expected,
      };
      final seenActualNames = <String>{};
      for (final actual in normalizedActual) {
        if (!seenActualNames.add(actual.name)) {
          throw StateError('Transfer manifest duplicate file: ${actual.name}.');
        }
        final expected = expectedByName[actual.name];
        if (expected == null || expected.sizeBytes != actual.sizeBytes) {
          throw StateError('Transfer manifest mismatch for ${actual.name}.');
        }
        final expectedHash = expected.sha256.trim();
        if (expectedHash.isNotEmpty &&
            expectedHash.toLowerCase() != actual.sha256.toLowerCase()) {
          throw StateError('Transfer manifest mismatch for ${actual.name}.');
        }
      }
    }

    final savedPaths = <String>[];
    final receivedItems = <TransferFileManifestItem>[];
    var totalBytes = 0;
    var allFilesHashVerified = true;
    var firstByteReceivedLogged = false;
    final expectedTotalBytes = normalizedActual.fold<int>(
      0,
      (sum, file) => sum + file.sizeBytes,
    );
    onProgress?.call(0, expectedTotalBytes);

    String? inProgressPath;
    try {
      for (final file in normalizedActual) {
        final destinationPath = destinationPathAllocator == null
            ? await _destinationPathAllocator.allocateDestinationPath(
                destinationDirectory: destinationDirectory,
                relativePath: file.name,
                destinationRelativeRootPrefix: destinationRelativeRootPrefix,
              )
            : await destinationPathAllocator(
                destinationDirectory: destinationDirectory,
                relativePath: file.name,
              );
        final tempPath = await _destinationPathAllocator
            .allocateTemporaryDestinationPath(destinationPath);
        inProgressPath = tempPath;
        final destinationFile = File(destinationPath);
        final tempFile = File(tempPath);
        await tempFile.parent.create(recursive: true);
        final sink = tempFile.openWrite(mode: FileMode.writeOnly);

        final digestSink = _DigestSink();
        final hashSink = sha256.startChunkedConversion(digestSink);
        var remaining = file.sizeBytes;
        while (remaining > 0) {
          final toRead = remaining < _chunkBytes ? remaining : _chunkBytes;
          onBeforeSocketRead?.call();
          final chunk = await reader.readExact(toRead);
          onAfterSocketRead?.call();
          sink.add(chunk);
          hashSink.add(chunk);
          remaining -= chunk.length;
          totalBytes += chunk.length;
          if (!firstByteReceivedLogged && chunk.isNotEmpty) {
            firstByteReceivedLogged = true;
            onDiagnosticEvent?.call(
              stage: 'receiver_first_byte_received',
              details: <String, Object?>{
                'fileName': file.name,
                'receivedBytes': totalBytes,
                'totalBytes': expectedTotalBytes,
              },
            );
          }
          onProgress?.call(totalBytes, expectedTotalBytes);
        }

        hashSink.close();
        await sink.flush();
        await sink.close();

        final actualSha = digestSink.value?.toString() ?? '';
        final expectedSha = file.sha256.trim();
        if (expectedSha.isEmpty) {
          allFilesHashVerified = false;
        }
        if (expectedSha.isNotEmpty &&
            actualSha.toLowerCase() != expectedSha.toLowerCase()) {
          try {
            await tempFile.delete();
          } catch (_) {}
          throw StateError('SHA-256 mismatch for ${file.name}');
        }
        await _fileIntegrity.verifyCompletedFile(
          path: tempPath,
          expectedBytes: file.sizeBytes,
          label: file.name,
        );
        if (await destinationFile.exists()) {
          throw StateError('Destination file already exists: $destinationPath');
        }
        await destinationFile.parent.create(recursive: true);
        final completedFile = await tempFile.rename(destinationPath);
        await _fileIntegrity.verifyCompletedFile(
          path: completedFile.path,
          expectedBytes: file.sizeBytes,
          label: file.name,
        );
        savedPaths.add(destinationPath);
        receivedItems.add(
          TransferFileManifestItem(
            fileName: file.name,
            sizeBytes: file.sizeBytes,
            sha256: actualSha,
          ),
        );
        inProgressPath = null;
      }

      return FileTransferResult(
        success: true,
        message: allFilesHashVerified
            ? 'Transfer completed. Hash verified.'
            : 'Transfer completed.',
        savedPaths: savedPaths,
        receivedItems: receivedItems,
        totalBytes: totalBytes,
        destinationDirectory: destinationDirectory.path,
        hashVerified: allFilesHashVerified,
      );
    } on Object {
      await _failedFileCleanup.cleanupSavedFiles(savedPaths);
      await _failedFileCleanup.cleanupInProgressFile(inProgressPath);
      rethrow;
    } finally {
      await reader.close();
      await socket.close();
    }
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

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

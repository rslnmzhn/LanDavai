import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SharedDownloadDiagnosticLogStore {
  SharedDownloadDiagnosticLogStore({
    Future<Directory> Function()? logDirectoryProvider,
    int Function()? retainedLineCountProvider,
    this.enabled = true,
  }) : _logDirectoryProvider = logDirectoryProvider ?? _defaultLogDirectory,
       _retainedLineCountProvider = retainedLineCountProvider;

  SharedDownloadDiagnosticLogStore.disabled()
    : _logDirectoryProvider = null,
      _retainedLineCountProvider = null,
      enabled = false;

  static const String _logFileName = 'debug.log';
  static const int _defaultRetainedLineCount = 200;

  final Future<Directory> Function()? _logDirectoryProvider;
  final int Function()? _retainedLineCountProvider;
  final bool enabled;

  Future<void> _pendingWrite = Future<void>.value();

  Future<Directory?> resolveLogDirectory({bool create = true}) async {
    if (!enabled || _logDirectoryProvider == null) {
      return null;
    }
    final directory = await _logDirectoryProvider();
    if (create) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File?> resolveLogFile({bool createDirectory = true}) async {
    final directory = await resolveLogDirectory(create: createDirectory);
    if (directory == null) {
      return null;
    }
    return File(p.join(directory.path, _logFileName));
  }

  Future<void> appendEvent({
    required String stage,
    String? requestId,
    Map<String, Object?> details = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (!enabled) {
      return;
    }
    final payload = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'stage': stage,
      ...details,
    };
    if (requestId != null && requestId.trim().isNotEmpty) {
      payload['requestId'] = requestId;
    }
    if (error != null) {
      payload['error'] = error.toString();
    }
    if (stackTrace != null) {
      payload['stackTrace'] = stackTrace.toString();
    }
    final line = '${jsonEncode(payload)}\n';
    _pendingWrite = _pendingWrite.then((_) => _appendLine(line));
    await _pendingWrite;
  }

  Future<void> _appendLine(String line) async {
    final file = await resolveLogFile();
    if (file == null) {
      return;
    }
    final existingLines = await file.exists()
        ? await file.readAsLines()
        : const <String>[];
    final nextLines = <String>[
      ...existingLines.where((value) => value.trim().isNotEmpty),
      line.trimRight(),
    ];
    final retainedLineCount = _resolveRetainedLineCount();
    final trimmed = nextLines.length <= retainedLineCount
        ? nextLines
        : nextLines.sublist(nextLines.length - retainedLineCount);
    await file.writeAsString('${trimmed.join('\n')}\n', flush: true);
  }

  int _resolveRetainedLineCount() {
    final raw = _retainedLineCountProvider?.call();
    if (raw == null || raw <= 0) {
      return _defaultRetainedLineCount;
    }
    return raw;
  }

  static Future<Directory> _defaultLogDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'Landa', 'logs'));
  }
}

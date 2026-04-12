import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SharedDownloadDiagnosticLogStore {
  SharedDownloadDiagnosticLogStore({
    Future<Directory> Function()? logDirectoryProvider,
    this.enabled = true,
  }) : _logDirectoryProvider = logDirectoryProvider ?? _defaultLogDirectory;

  SharedDownloadDiagnosticLogStore.disabled()
    : _logDirectoryProvider = null,
      enabled = false;

  static const String _logFileName = 'debug.log';
  static const int _maxLogLines = 200;

  final Future<Directory> Function()? _logDirectoryProvider;
  final bool enabled;

  Future<void> _pendingWrite = Future<void>.value();

  Future<File?> resolveLogFile() async {
    if (!enabled || _logDirectoryProvider == null) {
      return null;
    }
    final directory = await _logDirectoryProvider();
    await directory.create(recursive: true);
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
    final trimmed = nextLines.length <= _maxLogLines
        ? nextLines
        : nextLines.sublist(nextLines.length - _maxLogLines);
    await file.writeAsString('${trimmed.join('\n')}\n', flush: true);
  }

  static Future<Directory> _defaultLogDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'Landa', 'logs'));
  }
}

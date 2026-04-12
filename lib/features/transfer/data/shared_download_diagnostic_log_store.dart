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

  static const String _logFileName = 'shared_download_runtime.log';
  static const int _maxLogBytes = 1024 * 1024;

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
    required String requestId,
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
      'requestId': requestId,
      ...details,
    };
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
    await _rotateIfNeeded(file);
    await file.writeAsString(line, mode: FileMode.append, flush: true);
  }

  Future<void> _rotateIfNeeded(File file) async {
    if (!await file.exists()) {
      return;
    }
    final length = await file.length();
    if (length < _maxLogBytes) {
      return;
    }
    final rotated = File('${file.path}.1');
    if (await rotated.exists()) {
      await rotated.delete();
    }
    await file.rename(rotated.path);
  }

  static Future<Directory> _defaultLogDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'Landa', 'logs'));
  }
}

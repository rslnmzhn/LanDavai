import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/transfer/data/debug_log_access_service.dart';
import 'package:landa/features/transfer/data/shared_download_diagnostic_log_store.dart';

void main() {
  late Directory rootDirectory;

  setUp(() async {
    rootDirectory = await Directory.systemTemp.createTemp(
      'landa_debug_log_access_test_',
    );
  });

  tearDown(() async {
    if (await rootDirectory.exists()) {
      await rootDirectory.delete(recursive: true);
    }
  });

  test(
    'showLogs returns actionable message when debug.log is missing',
    () async {
      final opener = _RecordingPathOpener();
      final service = DebugLogAccessService(
        logStore: SharedDownloadDiagnosticLogStore(
          logDirectoryProvider: () async =>
              Directory(p.join(rootDirectory.path, 'logs')),
        ),
        pathOpener: opener,
      );

      final result = await service.showLogs();

      expect(result.opened, isFalse);
      expect(result.message, contains('debug.log ещё не создан'));
      expect(opener.openedPaths, isEmpty);
    },
  );

  test(
    'openLogsFolder returns actionable message when log directory is missing',
    () async {
      final opener = _RecordingPathOpener();
      final service = DebugLogAccessService(
        logStore: SharedDownloadDiagnosticLogStore(
          logDirectoryProvider: () async =>
              Directory(p.join(rootDirectory.path, 'logs')),
        ),
        pathOpener: opener,
      );

      final result = await service.openLogsFolder();

      expect(result.opened, isFalse);
      expect(result.message, contains('Папка логов ещё не создана'));
      expect(opener.openedPaths, isEmpty);
    },
  );

  test('showLogs opens debug.log when it already exists', () async {
    final logDirectory = Directory(p.join(rootDirectory.path, 'logs'))
      ..createSync(recursive: true);
    final logFile = File(p.join(logDirectory.path, 'debug.log'))
      ..writeAsStringSync('hello');
    final opener = _RecordingPathOpener();
    final service = DebugLogAccessService(
      logStore: SharedDownloadDiagnosticLogStore(
        logDirectoryProvider: () async => logDirectory,
      ),
      pathOpener: opener,
    );

    final result = await service.showLogs();

    expect(result.opened, isTrue);
    expect(opener.openedPaths, <String>[logFile.path]);
  });

  test('openLogsFolder opens existing log directory', () async {
    final logDirectory = Directory(p.join(rootDirectory.path, 'logs'))
      ..createSync(recursive: true);
    final opener = _RecordingPathOpener();
    final service = DebugLogAccessService(
      logStore: SharedDownloadDiagnosticLogStore(
        logDirectoryProvider: () async => logDirectory,
      ),
      pathOpener: opener,
    );

    final result = await service.openLogsFolder();

    expect(result.opened, isTrue);
    expect(opener.openedPaths, <String>[logDirectory.path]);
  });
}

class _RecordingPathOpener extends PathOpener {
  final List<String> openedPaths = <String>[];

  @override
  Future<void> openPath(String path) async {
    openedPaths.add(path);
  }
}

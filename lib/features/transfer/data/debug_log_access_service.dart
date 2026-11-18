import '../../../core/utils/path_opener.dart';
import 'shared_download_diagnostic_log_store.dart';

class DebugLogAccessResult {
  const DebugLogAccessResult._({required this.opened, this.message});

  const DebugLogAccessResult.opened() : this._(opened: true);

  const DebugLogAccessResult.message(String message)
    : this._(opened: false, message: message);

  final bool opened;
  final String? message;
}

class DebugLogAccessService {
  DebugLogAccessService({
    required SharedDownloadDiagnosticLogStore logStore,
    required PathOpener pathOpener,
  }) : _logStore = logStore,
       _pathOpener = pathOpener;

  final SharedDownloadDiagnosticLogStore _logStore;
  final PathOpener _pathOpener;

  Future<DebugLogAccessResult> showLogs() async {
    final logFile = await _logStore.resolveLogFile(createDirectory: false);
    if (logFile == null || !await logFile.exists()) {
      return const DebugLogAccessResult.message(
        'debug.log ещё не создан. Сначала воспроизведите проблему и попробуйте снова.',
      );
    }
    try {
      await _pathOpener.openPath(logFile.path);
      return const DebugLogAccessResult.opened();
    } on UnsupportedError {
      return const DebugLogAccessResult.message(
        'На этой платформе приложение не может открыть debug.log напрямую.',
      );
    } catch (error) {
      return DebugLogAccessResult.message(
        'Не удалось открыть debug.log: $error',
      );
    }
  }

  Future<DebugLogAccessResult> openLogsFolder() async {
    final logDirectory = await _logStore.resolveLogDirectory(create: false);
    if (logDirectory == null || !await logDirectory.exists()) {
      return const DebugLogAccessResult.message(
        'Папка логов ещё не создана. Сначала воспроизведите проблему и попробуйте снова.',
      );
    }
    try {
      await _pathOpener.openPath(logDirectory.path);
      return const DebugLogAccessResult.opened();
    } on UnsupportedError {
      return const DebugLogAccessResult.message(
        'На этой платформе приложение не может открыть папку логов напрямую.',
      );
    } catch (error) {
      return DebugLogAccessResult.message(
        'Не удалось открыть папку с логами: $error',
      );
    }
  }
}

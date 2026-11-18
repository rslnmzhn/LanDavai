import '../../../core/utils/path_opener.dart';
import 'shared_download_diagnostic_log_store.dart';

enum DebugLogAccessFailureCode {
  logMissing,
  logUnsupported,
  logOpenFailed,
  folderMissing,
  folderUnsupported,
  folderOpenFailed,
}

class DebugLogAccessResult {
  const DebugLogAccessResult._({
    required this.opened,
    this.message,
    this.failureCode,
    this.errorDetail,
  });

  const DebugLogAccessResult.opened() : this._(opened: true);

  const DebugLogAccessResult.message(
    String message, {
    DebugLogAccessFailureCode? failureCode,
    String? errorDetail,
  }) : this._(
         opened: false,
         message: message,
         failureCode: failureCode,
         errorDetail: errorDetail,
       );

  final bool opened;
  final String? message;
  final DebugLogAccessFailureCode? failureCode;
  final String? errorDetail;
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
        failureCode: DebugLogAccessFailureCode.logMissing,
      );
    }
    try {
      await _pathOpener.openPath(logFile.path);
      return const DebugLogAccessResult.opened();
    } on UnsupportedError {
      return const DebugLogAccessResult.message(
        'На этой платформе приложение не может открыть debug.log напрямую.',
        failureCode: DebugLogAccessFailureCode.logUnsupported,
      );
    } catch (error) {
      return DebugLogAccessResult.message(
        'Не удалось открыть debug.log: $error',
        failureCode: DebugLogAccessFailureCode.logOpenFailed,
        errorDetail: '$error',
      );
    }
  }

  Future<DebugLogAccessResult> openLogsFolder() async {
    final logDirectory = await _logStore.resolveLogDirectory(create: false);
    if (logDirectory == null || !await logDirectory.exists()) {
      return const DebugLogAccessResult.message(
        'Папка логов ещё не создана. Сначала воспроизведите проблему и попробуйте снова.',
        failureCode: DebugLogAccessFailureCode.folderMissing,
      );
    }
    try {
      await _pathOpener.openPath(logDirectory.path);
      return const DebugLogAccessResult.opened();
    } on UnsupportedError {
      return const DebugLogAccessResult.message(
        'На этой платформе приложение не может открыть папку логов напрямую.',
        failureCode: DebugLogAccessFailureCode.folderUnsupported,
      );
    } catch (error) {
      return DebugLogAccessResult.message(
        'Не удалось открыть папку с логами: $error',
        failureCode: DebugLogAccessFailureCode.folderOpenFailed,
        errorDetail: '$error',
      );
    }
  }
}
